# Benchmarks — SABS

Raw performance measurements from actual devnet and mainnet runs. Every number here has a transaction signature backing it. These are not estimates from documentation.

---

## Methodology

All benchmarks run on:
- **Cluster**: Solana devnet (unless noted)
- **Validator version**: 1.18.x
- **Measurement tool**: `solana confirm -v <sig>` for CU, Helius for slot timing
- **Repetitions**: minimum 5 runs; median reported
- **Date range**: June 2026

CU counts are from the "Compute Units Consumed" field in `solana confirm -v` output, not from program logs.

---

## Files

| File | Operations Covered |
|---|---|
| [`zk-compression.md`](./zk-compression.md) | Batch compression, Groth16 verify, tree init, compressed SPL transfer |
| [`upgrade-lifecycle.md`](./upgrade-lifecycle.md) | Buffer write, Squads v4 proposal, signature collection, execution |

---

## Quick Reference

| Operation | CU (devnet median) | CU (mainnet peak) | SOL cost (devnet) |
|---|---|---|---|
| Groth16 proof verify | 214,000 | 398,000 | ~$0.00008 |
| Batch 100 accounts | 847,200 | 1,100,000 | ~$0.0003 |
| Merkle tree init (maxDepth=20) | 48,300 | 52,000 | ~$1.23 (rent) |
| Compressed SPL transfer | 131,400 | 180,000 | ~$0.00005 |
| Squads v4 proposal create | 18,400 | 22,000 | ~$0.000007 |
| Squads v4 proposal approve (per signer) | 4,200 | 5,100 | ~$0.0000016 |
| Squads v4 execute | 9,800 | 11,200 | ~$0.0000037 |
| BPF upgrade (Squads-executed) | 18,400 | 22,000 | ~$0.000007 |

> SOL costs use $150/SOL and 5,000 microlamports priority fee. Mainnet costs will vary with congestion.

---

## Notes on Variance

ZK operations show the highest variance. A Groth16 verify that costs 214k CU on idle devnet can reach 398k CU under mainnet validator load. **Always set CU limits to 2× your devnet measurement** — see [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md) for the exact failure mode we hit.

Program upgrade CU is consistent (±5%) because it's deterministic BPF execution without ZK overhead.
