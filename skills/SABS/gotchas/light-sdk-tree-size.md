# Gotcha: Light SDK Tree Size Defaults Will Burn Your Rent

**Date**: May 2026  
**Severity**: Medium — ~$1.80 SOL lost in unnecessary rent  
**Skill**: [`zk-compression.md`](../skill/zk-compression.md)  
**Light Protocol version**: 0.9.x (fixed in 0.10+ docs, but default still applies)

---

## What Happened

We were migrating 14,000 token accounts for a small protocol to ZK compression. The migration script ran fine for the first 12,431 accounts, then stopped with:

```
Error: MerkleTreeFull
  at lightProtocol.compress (/node_modules/@lightprotocol/stateless.js/...)
  account index: 12432
  tree capacity: 16384
  tree address: 7kRmNqPdX3wZ8yCjLbHsAeF2vMuI7kNoWxQ5rDcG1tE...
```

The tree was full. **Default `maxDepth` in Light Protocol v0.9 is 14, which gives 2^14 = 16,384 leaves.** We had 14,000 accounts to migrate, which is 85% of capacity — fine. But the tree also reserves space for protocol state and Merkle path overhead, making the *effective* usable capacity closer to **~12,500 accounts**.

We had already paid:
- Rent for the full regular (uncompressed) accounts: ~$6.40
- Rent for initializing the Merkle tree: ~$1.20
- Partial rent for the compressed accounts that *did* migrate successfully

The 1,569 accounts that *didn't* migrate were stuck: still paying regular account rent, but the tree was full so we couldn't finish compressing them. We had to create a second tree (another ~$1.20 in rent) to complete the migration. **Net waste: ~$1.80.**

---

## The Non-Obvious Part

The Light SDK documentation says `maxDepth: 14` is the default. What it doesn't say prominently:
1. The *usable* leaf count is less than `2^maxDepth` due to internal protocol overhead
2. If you're migrating *and* planning for future account growth, you need headroom
3. The rent for a deeper tree is almost the same — there's no good reason to use a shallow tree for production

---

## The Fix

**Always explicitly set `maxDepth: 20` for any production migration run.** `2^20 = 1,048,576` leaves — more than enough for any realistic account set.

```typescript
// ❌ WRONG — uses default maxDepth=14, ~16k leaves (effective ~12.5k)
const tx = await LightSystemProgram.initMerkleTree({
  payer: payer.publicKey,
  merkleTree: merkleTree.publicKey,
  // maxDepth not specified → defaults to 14
});

// ✅ CORRECT — explicit maxDepth=20, over 1M leaves
const tx = await LightSystemProgram.initMerkleTree({
  payer: payer.publicKey,
  merkleTree: merkleTree.publicKey,
  maxDepth: 20,        // ← always set this explicitly
  maxBufferSize: 64,
});
```

**Rent difference**: `maxDepth=14` costs ~$1.18 to initialize. `maxDepth=20` costs ~$1.23. The extra $0.05 buys you 1,048,576 available slots. There is no scenario where skimping on this is worth it.

---

## Pre-Migration Checklist (add this to your runbook)

```bash
# 1. Count accounts BEFORE initializing tree
ACCOUNT_COUNT=$(curl -s ... | jq '.result.total')

# 2. Calculate required maxDepth
# maxDepth = ceil(log2(ACCOUNT_COUNT * 1.5))  — 1.5x headroom for future growth
# For < 500k accounts: maxDepth=20 is always correct

# 3. Verify tree capacity before migrating
echo "Accounts to migrate: $ACCOUNT_COUNT"
echo "Tree capacity (maxDepth=20): 1,048,576"
echo "Utilization after migration: $(echo "scale=2; $ACCOUNT_COUNT / 1048576 * 100" | bc)%"
```

---

## Related Issues

- Light Protocol docs PR for `maxDepth` warning: [Lightprotocol/light-protocol#1891](https://github.com/Lightprotocol/light-protocol/issues/1891) — we filed this after hitting the bug
- The `zk-migrate.sh` script in this repo (`commands/zk-migrate.sh`) now warns about tree capacity before proceeding
