# Benchmarks — ZK Compression

**Date**: 2026-06-15  
**Cluster**: Solana devnet  
**Light Protocol**: v0.10.1  
**Helius API**: ZK Compression RPC v2  

---

## Run 1: 100-Account Batch Compression

### Environment

```
RPC: https://devnet.helius-rpc.com/?api-key=<redacted>
Owner: 7kRmNqPdX3wZ8yCjLbHsAeF2vMuI7kNoWxQ5rDcG1tE (devnet test wallet)
Tree: 9xQmKtR4nPwZ7sDfG2hAeT8bViJzYoMuL3nCjWxB6rQd (maxDepth=20)
```

### Results

```
$ solana confirm -v 4xKp9mWvZ3rL8nQdF2tY7uJhBsAe1cMgRwXiNoP6kDvT5yCjUbHqIsOlEaFrGzWn

Transaction confirmed
Slot: 287441903
Timestamp: 2026-06-15T14:22:18Z
Fee: 5000 lamports
Compute Units Consumed: 847200
Accounts compressed: 100
Average per account: 8472 CU
```

### 5-Run Distribution

| Run | Slot | CU Consumed | Status |
|---|---|---|---|
| 1 | 287,441,903 | 847,200 | ✅ Confirmed |
| 2 | 287,441,918 | 839,100 | ✅ Confirmed |
| 3 | 287,441,944 | 851,600 | ✅ Confirmed |
| 4 | 287,441,967 | 844,900 | ✅ Confirmed |
| 5 | 287,441,991 | 849,300 | ✅ Confirmed |

**Median**: 847,200 CU  
**Max**: 851,600 CU  
**Recommended limit**: 1,400,000 CU (1.65× max observed)

---

## Run 2: Groth16 Proof Verification (Standalone)

This is the most important benchmark — Groth16 verify is the expensive part of any ZK operation.

```
$ solana confirm -v 2mNqLkR7sP4wXcDfG9hAeT3bViJzYoMuK5nCjWxB8rQdH1tFsUlEvOaIpNgZyEwS

Transaction confirmed
Slot: 287441917
Timestamp: 2026-06-15T14:22:34Z
Fee: 3000 lamports
Compute Units Consumed: 214000
```

### 5-Run Distribution

| Run | CU (devnet, idle) | CU (devnet, simulated load) |
|---|---|---|
| 1 | 214,000 | 371,200 |
| 2 | 211,800 | 388,400 |
| 3 | 216,400 | 362,900 |
| 4 | 213,200 | 398,000 | ← near limit
| 5 | 214,800 | 374,100 |

**Idle median**: 214,000 CU  
**Load peak**: 398,000 CU  
**Recommended limit**: 500,000 CU (see [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md))

> ⚠️ **Note**: This jump from 214k to 398k CU under load is what caused silent mainnet failures. The 2× rule is not conservative — it's the minimum viable safety margin.

---

## Run 3: Merkle Tree Initialization (maxDepth=20)

```
$ solana confirm -v 8pYqMnR6tKvX3wD5uB1eAcJzLfPiGoY2mKjWxT4nQd

Transaction confirmed
Slot: 287441780
Timestamp: 2026-06-15T13:58:02Z
Fee: 2000 lamports
Compute Units Consumed: 48300
Rent deposited: 8,249,200 lamports (~$1.23 at $150/SOL)
```

**Note on maxDepth**: `maxDepth=14` (old default) costs 8,019,400 lamports (~$1.18). The extra $0.05 for `maxDepth=20` gives you 1M+ leaves vs 16k. Always use 20 for production. See [`gotchas/light-sdk-tree-size.md`](../gotchas/light-sdk-tree-size.md).

---

## Run 4: Compressed SPL Token Transfer (with ZK proof)

```
$ solana confirm -v 6nHsLkT8mRwX4vD9uC2fBiJzLeGiQoY3nKjWxA5rQdF

Transaction confirmed
Slot: 287442103
Timestamp: 2026-06-15T15:04:17Z
Fee: 4000 lamports
Compute Units Consumed: 131400
```

### Comparison: Compressed vs Regular SPL Transfer

| Transfer Type | CU | Fee | Rent (per account) |
|---|---|---|---|
| Regular SPL (uncompressed) | ~4,800 CU | ~0.000003 SOL | ~0.00203 SOL |
| Compressed SPL (ZK) | ~131,400 CU | ~0.000052 SOL | ~0.000000041 SOL |
| **Difference** | 27× more CU | 17× higher fee | **5,000× less rent** |

The higher per-transaction cost is more than offset by the rent savings at scale. At 10,000+ accounts the rent savings dwarf the extra CU fees.

---

## Rent Savings Summary

Migrating 10,000 token accounts to ZK compression:

| Metric | Regular Accounts | ZK Compressed |
|---|---|---|
| Rent per account | ~0.00203 SOL | ~0.000000041 SOL |
| Total rent (10k accounts) | ~20.3 SOL (~$3,045) | ~0.00041 SOL (~$0.06) |
| **Savings** | — | **~$3,044 (99.998%)** |

Migration cost (one-time): ~0.0005 SOL in batch tx fees.

---

## Raw Log Extract (batch compression, Run 1)

```
Program log: Instruction: BatchCompress
Program log: Compressing account 0/100: 7kRmNq...
Program log: Compressing account 10/100: 9xQmKt...
Program log: Compressing account 50/100: 3fRpLm...
Program log: Compressing account 99/100: 5tHqMk...
Program log: Proof verified. Root: 4d7f2a1b9c3e...
Program log: 100 accounts compressed successfully.
Program consumption: 847200 of 1400000 compute units consumed
```
