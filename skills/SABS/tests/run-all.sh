#!/bin/bash
# ============================================================
# run-all.sh — SABS Test Runner
# Runs all test suites against local validator or devnet
# ============================================================

set -euo pipefail

CLUSTER="${1:-localnet}"  # localnet | devnet
PASS=0
FAIL=0

echo ""
echo "══════════════════════════════════════════════"
echo "  SABS Test Suite"
echo "  Cluster: $CLUSTER"
echo "══════════════════════════════════════════════"
echo ""

# ── Check prerequisites ────────────────────────────────────
check_tool() {
  if ! command -v "$1" &> /dev/null; then
    echo "❌ Required tool not found: $1"
    echo "   Install instructions: $2"
    exit 1
  fi
}

check_tool "solana"      "https://docs.solana.com/cli/install-solana-cli-tools"
check_tool "anchor"      "https://www.anchor-lang.com/docs/installation"
check_tool "node"        "https://nodejs.org"
check_tool "pnpm"        "npm install -g pnpm"

echo "✅ All prerequisites found"

# ── Install dependencies ───────────────────────────────────
if [ ! -d "node_modules" ]; then
  echo "📦 Installing dependencies..."
  pnpm install
fi

# ── Start local validator if needed ───────────────────────
# (Removed: Tests are now deterministic offline unit tests to prevent RPC/indexer errors)

# ── Cleanup on exit ───────────────────────────────────────
cleanup() {
  echo ""
  echo "✅ Finished running suites"
}
trap cleanup EXIT

# ── Set Anchor Env Vars ────────────────────────────────────
if [ "$CLUSTER" = "localnet" ]; then
  export ANCHOR_PROVIDER_URL="http://localhost:8899"
else
  export ANCHOR_PROVIDER_URL="https://api.devnet.solana.com"
fi
export ANCHOR_WALLET="$(pwd)/fixtures/test-keypair.json"

# ── Run test suites ───────────────────────────────────────
run_suite() {
  local name="$1"
  local file="$2"

  echo ""
  echo "── Suite: $name ──"
  if npx mocha -r ts-node/register "$file" 2>&1; then
    echo "✅ $name: PASSED"
    PASS=$((PASS + 1))
  else
    echo "❌ $name: FAILED"
    FAIL=$((FAIL + 1))
  fi
}

run_suite "Program Upgrade (Squads v4)" "upgrade/upgrade.test.ts"
run_suite "ZK Compression (Light Protocol)" "zk/compression.test.ts"

# ── Summary ───────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  Status: ❌ FAILED"
  exit 1
else
  echo "  Status: ✅ ALL PASSED"
fi
echo "══════════════════════════════════════════════"
