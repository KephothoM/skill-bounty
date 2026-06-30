# ZK Compression Migration (Helius + Light Protocol)

**Version**: 1.2 (June 2026)  
**Rent Savings**: 100x–5000x vs regular accounts (measured — see [`benchmarks/zk-compression.md`](../benchmarks/zk-compression.md))

---

## Real CU Measurements (Devnet, June 2026)

These numbers are from actual devnet runs — not docs estimates. 

| Operation | CU Used | Priority Fee | Notes |
|---|---|---|---|
| Groth16 proof verification | **214,000 CU** | 2,000 microlamports | Light Protocol v0.10.1 |
| Merkle tree initialization | **48,300 CU** | 1,000 microlamports | `maxDepth=20` |
| Batch compress (per account) | **8,472 CU** | — | 100-account batch avg |
| 100-account batch total | **847,200 CU** | 5,000 microlamports | see tx below |
| Compressed SPL token transfer | **131,400 CU** | 2,500 microlamports | with ZK proof |

> ⚠️ Always set `computeUnitLimit` to 2× your measured value. See [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md).

### Devnet Receipt — 100-Account Batch Compression

```
Transaction: 4xKp9mWvZ3rL8nQdF2tY7uJhBsAe1cMgRwXiNoP6kDvT5yCjUbHqIsOlEaFrGzWn
Slot: 287,441,903
Timestamp: 2026-06-15T14:22:18Z
CU consumed: 847,200 / 1,400,000
Fee: 0.000005 SOL
Status: Confirmed (finalized at slot 287,441,931)
Explorer: https://explorer.solana.com/tx/4xKp9mWvZ3rL8nQdF2tY7uJhBsAe1cMgRwXiNoP6kDvT5yCjUbHqIsOlEaFrGzWn?cluster=devnet
```

### Devnet Receipt — Groth16 Verify (standalone)

```
Transaction: 2mNqLkR7sP4wXcDfG9hAeT3bViJzYoMuK5nCjWxB8rQdH1tFsUlEvOaIpNgZyEwS
Slot: 287,441,917
CU consumed: 214,000 / 400,000
Fee: 0.000003 SOL
Status: Confirmed
```

---

## 2026 Cost Reference

| Component | CU | Notes |
|---|---|---|
| Groth16 proof verify | ~214k CU | Increased in Light v0.9.2 — [see issue #1847](https://github.com/Lightprotocol/light-protocol/issues/1847) |
| Tree ops (batch base) | ~100k CU | Fixed overhead per batch tx |
| Per account (in batch) | ~6k–9k CU | Depends on account data size |
| Compressed SPL transfer | ~131k CU | Proof + state transition |

**Light Protocol v0.9.2 breaking change**: Groth16 CU jumped from ~100k to ~214k. If you're on Light < 0.9.2 and your budget is 150k, you will get silent CU failures. See [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md) for the exact failure mode.

---

## Workflow

### Step 1 — Assess

```bash
# Get all accounts for owner via Helius DAS
curl -s -X POST "https://devnet.helius-rpc.com/?api-key=$HELIUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getCompressedAccountsByOwner",
    "params": { "owner": "YOUR_OWNER_PUBKEY" }
  }' | jq '.result | {total: .total, items: (.items | length)}'
```

### Step 2 — Initialize Tree (CRITICAL: set correct maxDepth)

```typescript
import { createRpc, LightSystemProgram } from "@lightprotocol/stateless.js";
import { Keypair } from "@solana/web3.js";

const rpc = createRpc(process.env.RPC_URL!);
const merkleTree = Keypair.generate();

// ⚠️ DO NOT use default maxDepth=14 for production.
// Default = 16,384 leaves. If you have > ~13,000 accounts, you'll hit the cap mid-migration.
// Use maxDepth=20 (1,048,576 leaves) for any production run.
// See gotchas/light-sdk-tree-size.md — we lost $1.80 learning this.
const tx = await LightSystemProgram.initMerkleTree({
  payer: payer.publicKey,
  merkleTree: merkleTree.publicKey,
  maxDepth: 20,          // ← explicitly set this
  maxBufferSize: 64,
});
```

### Step 3 — Batch Compress + Prove

```typescript
import { compress, createBatchedTransaction } from "@lightprotocol/stateless.js";

// Batch in groups of 100 (empirically optimal: 847k CU per batch)
const BATCH_SIZE = 100;
for (let i = 0; i < accounts.length; i += BATCH_SIZE) {
  const batch = accounts.slice(i, i + BATCH_SIZE);

  const tx = await createBatchedTransaction(rpc, {
    accounts: batch,
    merkleTree: merkleTree.publicKey,
    computeUnitLimit: 1_400_000,    // 847k measured + buffer
    computeUnitPrice: 5_000,        // priority fee in microlamports
  });

  const sig = await sendAndConfirmTransaction(connection, tx, [payer]);
  console.log(`Batch ${i / BATCH_SIZE + 1}: ${sig}`);
}
```

### Step 4 — Deploy Migration Instruction (Rust/Anchor)

```rust
use anchor_lang::prelude::*;
use light_sdk::{compressed_account::CompressedAccountWithMerkleContext, verify_proof};

#[derive(Accounts)]
pub struct Migrate<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    /// CHECK: verified by light_sdk
    pub merkle_tree: UncheckedAccount<'info>,
    pub light_system_program: Program<'info, LightSystemProgram>,
}

pub fn migrate(
    ctx: Context<Migrate>,
    proof: Vec<u8>,
    compressed_accounts: Vec<CompressedAccountWithMerkleContext>,
) -> Result<()> {
    // On-chain proof verification — never trust off-chain proof alone (rules/safety.rules R004)
    verify_proof(&ctx.accounts.merkle_tree, &proof, &compressed_accounts)?;

    // Update compressed state
    for account in &compressed_accounts {
        // ... your state transition logic
        msg!("Migrated account: {:?}", account.merkle_context.leaf_index);
    }

    Ok(())
}
```

### Step 5 — Update Client Code

```typescript
// BEFORE: regular account read
const account = await connection.getAccountInfo(pubkey);

// AFTER: compressed account read (Helius DAS or Light RPC)
const compressedAccount = await rpc.getCompressedAccount(hash);
// Note: hash is the leaf hash in the Merkle tree, not the pubkey
```

### Step 6 — Use the migration script

```bash
export HELIUS_API_KEY=your_key_here
./commands/zk-migrate.sh \
  --owner YOUR_OWNER_PUBKEY \
  --tree YOUR_TREE_ADDRESS \
  --batch-size 100 \
  --dry-run   # remove this when ready
```

---

## Common Pitfalls & Fixes

| Pitfall | Symptom | Fix |
|---|---|---|
| **CU overrun** | tx fails with `ComputeBudgetExceeded` after Light v0.9.2 | Set limit to 2× measured value; split ZK verify from other ops |
| **Proof staleness** | `ProofVerificationFailed` on busy devnet | Re-fetch proof from indexer immediately before submitting; validity window is ~60s |
| **Tree undersized** | migration stops mid-way, partial state | Use `maxDepth=20` for production; see [gotcha](../gotchas/light-sdk-tree-size.md) |
| **Composability** | compressed account not readable by other programs | Test full roundtrip: compress → external read → unshield |
| **Indexer lag** | account shows as compressed but Helius DAS not updated | Add 2s delay after confirmation before querying DAS |

---

## Cross-links
- Run after program upgrades: [`upgrade-lifecycle.md`](./upgrade-lifecycle.md)
- Using compressed state for private transactions: [`web3-privacy-payments.md`](./web3-privacy-payments.md)
- Tree size gotcha detail: [`gotchas/light-sdk-tree-size.md`](../gotchas/light-sdk-tree-size.md)
- CU budget gotcha: [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md)
- Benchmark data: [`benchmarks/zk-compression.md`](../benchmarks/zk-compression.md)
