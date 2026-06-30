# Gotcha: Helius Proof Staleness Window Is Shorter Than You Think

**Date**: June 2026  
**Severity**: Medium — random `ProofVerificationFailed` errors on busy devnet  
**Skill**: [`zk-compression.md`](../skill/zk-compression.md)  
**Helius API**: ZK Compression RPC methods (`getValidityProof`, `getMultipleCompressedAccountProofs`)

---

## What Happened

Our ZK compression migration was working reliably on devnet during off-peak hours. During a stress test where we submitted 10 batches in parallel, roughly 3 out of 10 batches failed with:

```
Error: ProofVerificationFailed
  at LightSystemProgram.verify (...)
  Transaction: 7mNqLkR5sP4wXcDfG9hAeT3bViJzYoMuK5nCjWxB8rQd...
  Slot at proof fetch: 287,441,890
  Slot at tx submission: 287,441,958
```

The slot difference was **68 slots** — roughly 27 seconds. The proof had gone stale.

We assumed the proof validity window was "a few minutes" based on vague documentation. It's not. Under load, proof staleness on Helius devnet was failing at **~60 seconds** from fetch to submission.

---

## The Non-Obvious Part

The validity proof is tied to a **Merkle root at a specific slot**. As new accounts are compressed into the tree, the root advances. The proof you fetched at slot N is only valid while the Merkle root at slot N is still recent enough that the on-chain verifier considers it canonical.

Light Protocol's on-chain verifier has a configurable lookback window. The Helius hosted indexer sets this to **~100 slots** (~40 seconds). Under high load, where you're submitting many compression transactions and the tree root is advancing rapidly, **the effective validity window shrinks further**.

There's an important nuance: the proof doesn't expire at a wall-clock time — it expires when the *on-chain Merkle root has advanced past the root your proof was generated against*. In a high-activity tree, this can happen in 10 seconds.

---

## The Fix

**Always fetch the proof as the last step before submitting the transaction.** Never pre-fetch a batch of proofs and then submit them sequentially — by the time you get to proof #5, proofs #1-3 may have expired.

```typescript
// ❌ WRONG — prefetch all proofs, then submit sequentially
const proofs = await Promise.all(accounts.map(a => rpc.getValidityProof([a.hash])));
for (let i = 0; i < accounts.length; i++) {
  const tx = buildCompressTx(accounts[i], proofs[i]); // proof[5] may be stale
  await sendAndConfirm(tx);
}

// ✅ CORRECT — fetch proof immediately before each submission
for (const account of accounts) {
  // Fetch proof at the last possible moment
  const { compressedProof, roots } = await rpc.getValidityProof([account.hash]);

  const tx = buildCompressTx(account, compressedProof, roots);
  await sendAndConfirm(tx); // submit within ~10 seconds of proof fetch
}
```

**For parallel batches**, fetch the proof inside the same async function that submits:

```typescript
async function compressAccountSafely(
  rpc: Rpc,
  account: CompressedAccount,
  merkleTree: PublicKey
): Promise<string> {
  // These two calls should be as close together as possible
  const { compressedProof, roots } = await rpc.getValidityProof([account.hash]);
  const tx = await buildCompressTx(account, compressedProof, roots, merkleTree);

  return sendAndConfirmTransaction(connection, tx, [payer]);
}

// Run batches in parallel — each fetches its own fresh proof
const results = await Promise.allSettled(
  accounts.map(a => compressAccountSafely(rpc, a, merkleTree))
);
```

---

## Retry Logic for Stale Proofs

Add a retry wrapper specifically for proof staleness:

```typescript
async function compressWithRetry(
  rpc: Rpc,
  account: CompressedAccount,
  merkleTree: PublicKey,
  maxRetries = 3
): Promise<string> {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await compressAccountSafely(rpc, account, merkleTree);
    } catch (err) {
      const isStaleProof = err.message?.includes("ProofVerificationFailed") ||
                           err.message?.includes("InvalidMerkleRoot");

      if (isStaleProof && attempt < maxRetries) {
        console.warn(`Stale proof on attempt ${attempt}, retrying immediately...`);
        // Don't add delay — fetch fresh proof immediately
        continue;
      }
      throw err;
    }
  }
  throw new Error("Max retries exceeded");
}
```

---

## Monitoring

To detect proof staleness issues in production:

```bash
# Add to your Helius webhook handler — alert on ProofVerificationFailed
# Filter for error code 6003 (Light Protocol proof verification error)
curl -X POST "https://api.helius.xyz/v0/webhooks" \
  -H "Content-Type: application/json" \
  -d '{
    "webhookURL": "https://your-alerts.com/webhook",
    "transactionTypes": ["COMPRESSED_NFT_MINT"],
    "accountAddresses": ["your_merkle_tree_address"],
    "webhookType": "enhanced"
  }'
```

---

## Related

- [Light Protocol validity proof docs](https://docs.lightprotocol.com/learn/core-concepts/validity-proofs) — mentions the lookback window but doesn't state the exact slot count
- [Helius ZK Compression RPC reference](https://docs.helius.dev/compression-and-das-api/compression-api) — `getValidityProof` response format
- The `commands/zk-migrate.sh` script in this repo always fetches proofs immediately before submission
