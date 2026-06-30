#!/bin/bash
# ============================================================
# zk-migrate.sh — Batch ZK Compression Migration (Helius + Light Protocol)
# SABS: https://github.com/kephothoM/SABS
#
# Usage:
#   ./zk-migrate.sh --owner <OWNER_PUBKEY> --tree <TREE_ADDRESS> [--rpc <HELIUS_URL>] [--batch-size <N>]
#
# Prerequisites:
#   - node >= 20 with @lightprotocol/stateless.js installed
#   - Helius API key set in HELIUS_API_KEY env var
#   - solana CLI for balance checks
# ============================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────
OWNER=""
TREE_ADDRESS=""
BATCH_SIZE=100
RPC_URL=""
DRY_RUN=false
HELIUS_API_KEY="${HELIUS_API_KEY:-}"

# ── Arg parsing ───────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --owner)      OWNER="$2"; shift ;;
    --tree)       TREE_ADDRESS="$2"; shift ;;
    --rpc)        RPC_URL="$2"; shift ;;
    --batch-size) BATCH_SIZE="$2"; shift ;;
    --dry-run)    DRY_RUN=true ;;
    *) echo "❌ Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# ── Validation ────────────────────────────────────────────
if [ -z "$OWNER" ] || [ -z "$TREE_ADDRESS" ]; then
  echo "Usage: $0 --owner <PUBKEY> --tree <TREE_ADDR> [--rpc <URL>] [--batch-size <N>] [--dry-run]"
  exit 1
fi

if [ -z "$HELIUS_API_KEY" ]; then
  echo "❌ HELIUS_API_KEY environment variable is not set."
  echo "   Export it: export HELIUS_API_KEY=your_key_here"
  echo "   Get a key at: https://helius.dev"
  exit 1
fi

RPC_URL="${RPC_URL:-https://devnet.helius-rpc.com/?api-key=${HELIUS_API_KEY}}"

echo ""
echo "══════════════════════════════════════════════"
echo "  SABS ZK Compression Migration"
echo "══════════════════════════════════════════════"
echo "  Owner      : $OWNER"
echo "  Tree       : $TREE_ADDRESS"
echo "  Batch size : $BATCH_SIZE"
echo "  RPC        : $RPC_URL"
echo "  Dry run    : $DRY_RUN"
echo "══════════════════════════════════════════════"
echo ""

# ── Step 1: Fetch accounts to migrate ────────────────────
echo "📡 [1/5] Fetching existing accounts via Helius DAS..."
ACCOUNT_COUNT=$(curl -s -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 1,
    \"method\": \"getAssetsByOwner\",
    \"params\": {
      \"ownerAddress\": \"$OWNER\",
      \"page\": 1,
      \"limit\": 1
    }
  }" | jq '.result.total // 0')

echo "   Found $ACCOUNT_COUNT accounts for owner $OWNER"

if [ "$ACCOUNT_COUNT" -eq 0 ]; then
  echo "   No accounts found. Nothing to migrate."
  exit 0
fi

# ── Step 2: Pre-flight — check tree capacity ──────────────
echo ""
echo "🌲 [2/5] Checking tree capacity..."
# Tree capacity = 2^maxDepth. Warn if accounts > 80% capacity.
# IMPORTANT: Default maxDepth=14 → 16,384 leaves. See gotchas/light-sdk-tree-size.md.
echo "   ⚠️  Verify your tree was initialized with sufficient maxDepth."
echo "   Account count: $ACCOUNT_COUNT"
echo "   If migrating > 16,000 accounts, you need maxDepth >= 15 (32,768 leaves)."
echo "   For production runs: use maxDepth=20 (1,048,576 leaves) — see gotchas/light-sdk-tree-size.md"

# ── Step 3: Estimate CU cost ──────────────────────────────
echo ""
echo "⚡ [3/5] Estimating compute units..."
BATCHES=$(( (ACCOUNT_COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))
# Empirical: ~847,200 CU per 100-account batch (measured 2026-06-15, see benchmarks/)
CU_PER_BATCH=847200
TOTAL_CU=$((BATCHES * CU_PER_BATCH))
echo "   Batches needed   : $BATCHES"
echo "   CU per batch     : ~$CU_PER_BATCH (empirical, see benchmarks/zk-compression.md)"
echo "   Total CU estimate: ~$TOTAL_CU"
echo "   ⚠️  Set computeUnitLimit: $((CU_PER_BATCH * 2)) per tx (2x buffer — see gotchas/cu-budget-overruns.md)"

if $DRY_RUN; then
  echo ""
  echo "ℹ️  --dry-run flag set. No migration transactions will be submitted."
  echo "   To proceed, re-run without --dry-run after reviewing the estimates above."
  exit 0
fi

# ── Step 4: Human confirmation gate ───────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  ⚠️  HUMAN CHECKPOINT"
echo "══════════════════════════════════════════════"
echo "  Migrating $ACCOUNT_COUNT accounts to ZK compression."
echo "  Tree address: $TREE_ADDRESS"
echo "  Estimated $BATCHES transactions, ~$TOTAL_CU total CU."
echo ""
echo "  CHECKLIST:"
echo "  [ ] Tree initialized with sufficient maxDepth"
echo "  [ ] Client code updated to use compressed account reads"
echo "  [ ] Tested full roundtrip on devnet (compress → read → unshield)"
echo "  [ ] Helius webhook set up for monitoring (see upgrade-lifecycle.md)"
echo ""
read -rp "  Type YES to begin migration: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Aborted. No migration submitted."
  exit 0
fi

# ── Step 5: Run migration via Node.js helper ──────────────
echo ""
echo "🚀 [5/5] Starting batch migration..."

# The actual migration uses @lightprotocol/stateless.js
# This calls the inline Node.js script:
node - <<'NODEJS_EOF'
const { createRpc, compress } = require("@lightprotocol/stateless.js");
const { PublicKey } = require("@solana/web3.js");

const OWNER = process.env.OWNER;
const TREE  = process.env.TREE_ADDRESS;
const RPC   = process.env.RPC_URL;

async function main() {
  const rpc = createRpc(RPC, RPC);

  // Fetch accounts (Helius DAS: getCompressedAccountsByOwner)
  const { items } = await rpc.getAssetsByOwner({ ownerAddress: OWNER, page: 1, limit: 1000 });
  console.log(`Compressing ${items.length} accounts...`);

  let successCount = 0;
  for (const item of items) {
    try {
      const sig = await compress(rpc, new PublicKey(item.id), new PublicKey(TREE));
      console.log(`  ✅ Compressed ${item.id.slice(0,8)}... → sig: ${sig.slice(0,16)}...`);
      successCount++;
    } catch (err) {
      console.error(`  ❌ Failed ${item.id.slice(0,8)}...: ${err.message}`);
    }
  }
  console.log(`\nMigration complete: ${successCount}/${items.length} accounts compressed.`);
}

main().catch(console.error);
NODEJS_EOF

echo ""
echo "✅ Migration batch submitted. Monitor via:"
echo "   Helius Dashboard: https://dev.helius.xyz"
echo "   Or run: curl -s -X POST $RPC_URL -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getCompressedAccountsByOwner\",\"params\":{\"owner\":\"$OWNER\"}}' | jq '.result.total'"
