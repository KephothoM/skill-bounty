#!/bin/bash
# ============================================================
# safe-upgrade.sh — Squads v4 Program Upgrade with Full Safety Gates
# SABS: https://github.com/kephothoM/SABS
#
# Usage:
#   ./safe-upgrade.sh --program <PROG_ID> --buffer <BUFFER_ADDR> [--multisig <PDA>] [--rpc <URL>]
#
# Prerequisites:
#   - solana CLI >= 1.18
#   - squads-multisig-cli >= 0.5 (npm i -g @sqds/multisig-cli)
#   - .squads.json in project root (auto-detected if --multisig not specified)
# ============================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────
SQUADS_CONFIG=".squads.json"
RPC_URL=""
PROGRAM_ID=""
BUFFER=""
MULTISIG_PDA=""
DRY_RUN=false

# ── Arg parsing ───────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --program)   PROGRAM_ID="$2"; shift ;;
    --buffer)    BUFFER="$2"; shift ;;
    --multisig)  MULTISIG_PDA="$2"; shift ;;
    --rpc)       RPC_URL="$2"; shift ;;
    --dry-run)   DRY_RUN=true ;;
    *) echo "❌ Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# ── Validation ────────────────────────────────────────────
if [ -z "$PROGRAM_ID" ] || [ -z "$BUFFER" ]; then
  echo "Usage: $0 --program <ID> --buffer <BUFFER_ADDR> [--multisig <PDA>] [--rpc <URL>] [--dry-run]"
  exit 1
fi

# ── Auto-detect multisig from .squads.json ────────────────
if [ -z "$MULTISIG_PDA" ]; then
  if [ ! -f "$SQUADS_CONFIG" ]; then
    echo "❌ No --multisig provided and no .squads.json found in current directory."
    echo "   Create one from .squads.json.example or pass --multisig explicitly."
    exit 1
  fi
  MULTISIG_PDA=$(jq -r '.multisigPda' "$SQUADS_CONFIG")
  RPC_URL_FROM_CONFIG=$(jq -r '.rpcUrl // empty' "$SQUADS_CONFIG")
  echo "📂 Loaded multisig PDA from $SQUADS_CONFIG: $MULTISIG_PDA"
fi

# RPC: flag > config > default devnet
if [ -z "$RPC_URL" ]; then
  RPC_URL="${RPC_URL_FROM_CONFIG:-https://api.devnet.solana.com}"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  SABS Safe Upgrade — Squads v4"
echo "══════════════════════════════════════════════"
echo "  Program ID  : $PROGRAM_ID"
echo "  Buffer Addr : $BUFFER"
echo "  Multisig PDA: $MULTISIG_PDA"
echo "  RPC         : $RPC_URL"
echo "  Dry run     : $DRY_RUN"
echo "══════════════════════════════════════════════"
echo ""

# ── Step 1: Verify buffer exists and get checksum ─────────
echo "🔍 [1/5] Verifying buffer account..."
BUFFER_INFO=$(solana program show "$BUFFER" --url "$RPC_URL" 2>&1) || {
  echo "❌ Buffer account not found at $BUFFER on $RPC_URL"
  echo "   Did you run: solana program write-buffer ./target/deploy/<program>.so ?"
  exit 1
}
echo "$BUFFER_INFO"

# Compute local binary checksum (must match buffer)
LOCAL_SO=$(find ./target/deploy -name "*.so" | head -1)
if [ -n "$LOCAL_SO" ]; then
  LOCAL_CHECKSUM=$(sha256sum "$LOCAL_SO" | awk '{print $1}')
  echo ""
  echo "🔑 Local binary SHA256 : $LOCAL_CHECKSUM"
  echo "   ⚠️  Manually verify this matches the buffer's deployed hash before signing."
  echo "   Run: solana program dump $BUFFER /tmp/buffer.so && sha256sum /tmp/buffer.so"
else
  echo "⚠️  No .so found in ./target/deploy — make sure you ran: anchor build --verifiable"
fi

# ── Step 2: Devnet/fork simulation ────────────────────────
echo ""
echo "🧪 [2/5] Running upgrade simulation (--dry-run)..."
solana program upgrade "$PROGRAM_ID" \
  --buffer "$BUFFER" \
  --upgrade-authority "$MULTISIG_PDA" \
  --url "$RPC_URL" \
  --dry-run 2>&1 || {
    echo "❌ Simulation FAILED — do NOT proceed to proposal creation."
    echo "   Common causes:"
    echo "   - Buffer size mismatch (run: solana program show $PROGRAM_ID)"
    echo "   - Wrong upgrade authority (check: solana program show $PROGRAM_ID | grep Authority)"
    echo "   - Insufficient balance in upgrade authority account"
    exit 1
  }
echo "✅ Simulation passed."

if $DRY_RUN; then
  echo ""
  echo "ℹ️  --dry-run flag set. Stopping before Squads proposal creation."
  exit 0
fi

# ── Step 3: Human confirmation gate ───────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  ⚠️  HUMAN CHECKPOINT — READ BEFORE CONTINUING"
echo "══════════════════════════════════════════════"
echo "  You are about to create a Squads v4 proposal to upgrade:"
echo "  Program  : $PROGRAM_ID"
echo "  Buffer   : $BUFFER"
echo "  Multisig : $MULTISIG_PDA"
echo ""
echo "  CHECKLIST:"
echo "  [ ] Buffer SHA256 matches local binary"
echo "  [ ] anchor build --verifiable hash confirmed"
echo "  [ ] State migration instruction included (if needed)"
echo "  [ ] Devnet simulation reviewed above"
echo ""
read -rp "  Type YES to create the Squads v4 proposal: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Aborted. No proposal created."
  exit 0
fi

# ── Step 4: Create Squads v4 Proposal ────────────────────
echo ""
echo "📋 [4/5] Creating Squads v4 upgrade proposal..."

# Get current transaction index from multisig
TX_INDEX=$(squads-multisig-cli multisig info \
  --multisig "$MULTISIG_PDA" \
  --url "$RPC_URL" \
  --output json | jq '.transactionIndex')

echo "   Current transaction index: $TX_INDEX"
NEXT_INDEX=$((TX_INDEX + 1))

# Create the proposal using Squads v4 CLI
# This calls: squads_multisig::instructions::vault_transaction_create
squads-multisig-cli transaction create \
  --multisig "$MULTISIG_PDA" \
  --url "$RPC_URL" \
  --program-id BPFLoaderUpgradeab1e11111111111111111111111 \
  --instruction upgrade \
  --program-address "$PROGRAM_ID" \
  --buffer "$BUFFER" \
  --spill-address "$(solana address)" \
  --memo "SABS safe-upgrade: $PROGRAM_ID @ $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  2>&1 | tee /tmp/sabs-proposal-output.txt

PROPOSAL_PDA=$(grep -oP 'Proposal: \K[A-Za-z0-9]+' /tmp/sabs-proposal-output.txt || echo "check output above")

echo ""
echo "✅ [5/5] Proposal created."
echo ""
echo "══════════════════════════════════════════════"
echo "  NEXT STEPS (all signers must complete):"
echo "══════════════════════════════════════════════"
echo "  1. Share proposal PDA with all signers: $PROPOSAL_PDA"
echo "  2. Each signer runs:"
echo "     squads-multisig-cli transaction approve \\"
echo "       --multisig $MULTISIG_PDA \\"
echo "       --transaction-index $NEXT_INDEX \\"
echo "       --url $RPC_URL"
echo ""
echo "  3. Once threshold reached, execute:"
echo "     squads-multisig-cli transaction execute \\"
echo "       --multisig $MULTISIG_PDA \\"
echo "       --transaction-index $NEXT_INDEX \\"
echo "       --url $RPC_URL"
echo ""
echo "  4. Post-upgrade: Run smoke tests and monitor Helius webhooks for 1h."
echo "  Squads UI: https://v4.squads.so/multisigs/$MULTISIG_PDA"
echo "══════════════════════════════════════════════"
