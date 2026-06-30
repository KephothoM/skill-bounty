# Gotcha: CU Budget Overruns on ZK Operations Under Validator Load

**Date**: June 2026  
**Severity**: High — silent failures on mainnet (tx returns success, state not updated)  
**Affects**: Any transaction combining Groth16 verification with other instructions  
**Discovered**: During load testing before mainnet launch of ZK compression migration

---

## What Happened

Our ZK compression migration transactions were structured as:

```
[Groth16 verify] + [state update] + [emit event]
ComputeBudget: 400,000 CU
```

On devnet during low-load testing: **214,000 CU consumed**. Plenty of headroom.

On mainnet during our first production run: random transactions were **silently failing** the state update. The transaction signature was confirmed, the fee was paid, but the state wasn't updated.

After debugging for 6 hours we found: under mainnet validator load, the Groth16 verification was consuming up to **398,000 CU** — barely under the 400,000 limit. On two occasions it exceeded the limit, and the Solana runtime **partially executed the transaction**: the compute budget instruction ran (fees charged), but the remaining instructions were dropped.

This is documented Solana behavior but easy to forget: when CU is exceeded, the **transaction is included in the block** (you pay fees) but **execution stops at the exceeded instruction** (state changes are rolled back).

---

## The Non-Obvious Part

CU consumption for Groth16 verification is **not deterministic** across different validator states. The same proof with the same inputs can consume different CU amounts depending on:

1. **Validator scheduling pressure** — when a validator is under load, certain syscalls take more CU
2. **Proof complexity** — our proofs had variable input sizes; larger inputs → more CU
3. **Solana runtime version** — CU costs for BPF syscalls are occasionally adjusted

The Light Protocol docs say "Groth16 verification costs ~100k–200k CU." As of v0.9.2, this jumped to **~214k on average, with spikes to ~400k under load**. The docs hadn't been updated.

---

## The Fix

**Two rules, both mandatory:**

### Rule 1: Set CU limit to 2× your measured average

```typescript
// ❌ WRONG — based on measured average, no headroom
const computeBudgetIx = ComputeBudgetProgram.setComputeUnitLimit({
  units: 214_000,  // your devnet measurement
});

// ✅ CORRECT — 2× buffer for production variance
const computeBudgetIx = ComputeBudgetProgram.setComputeUnitLimit({
  units: 500_000,  // 214k * 2.3x safety factor
});
```

### Rule 2: Never combine Groth16 verify with BPF program upgrade in the same transaction

```typescript
// ❌ WRONG — CU competition between two heavy operations
const tx = new Transaction().add(
  ComputeBudgetProgram.setComputeUnitLimit({ units: 400_000 }),
  groth16VerifyInstruction,     // ~214k CU
  bpfProgramUpgradeInstruction, // ~50k CU
  // Total: ~264k avg, ~450k peak → EXCEEDED
);

// ✅ CORRECT — separate transactions for separate operations
const verifyTx = new Transaction().add(
  ComputeBudgetProgram.setComputeUnitLimit({ units: 500_000 }),
  groth16VerifyInstruction,
);
const upgradeTx = new Transaction().add(
  ComputeBudgetProgram.setComputeUnitLimit({ units: 200_000 }),
  bpfProgramUpgradeInstruction,
);

const verifySig = await sendAndConfirmTransaction(connection, verifyTx, [payer]);
const upgradeSig = await sendAndConfirmTransaction(connection, upgradeTx, [payer]);
```

This is also documented in the v1.1.0 CHANGELOG — we split these ops after hitting this on devnet first.

---

## How to Detect Silent Failures

The dangerous thing about CU overruns is that the transaction *looks* successful. Add explicit state verification after every ZK transaction:

```typescript
async function sendAndVerifyZKTx(
  connection: Connection,
  tx: Transaction,
  expectedStateChange: () => Promise<boolean>
): Promise<string> {
  const sig = await sendAndConfirmTransaction(connection, tx, [payer]);

  // Verify state actually changed — don't trust the signature alone
  const confirmed = await expectedStateChange();
  if (!confirmed) {
    throw new Error(
      `Transaction ${sig} was confirmed but state was not updated. ` +
      `This is likely a CU overrun. Check compute unit consumption ` +
      `with: solana confirm -v ${sig}`
    );
  }

  return sig;
}

// Usage
await sendAndVerifyZKTx(
  connection,
  zkMigrationTx,
  async () => {
    const compressed = await rpc.getCompressedAccount(accountHash);
    return compressed !== null;
  }
);
```

---

## CU Budget Reference (SABS-measured, devnet + mainnet)

| Operation | Devnet (low load) | Mainnet (peak load) | Recommended Limit |
|---|---|---|---|
| Groth16 verify (Light v0.10) | 214,000 | 398,000 | **500,000** |
| Compressed SPL transfer | 131,400 | 180,000 | **280,000** |
| BPFUpgradeLoader upgrade | 18,400 | 22,000 | **50,000** |
| Batch compress (100 accts) | 847,200 | 1,100,000 | **1,400,000** |
| Switchboard oracle read | 8,200 | 12,000 | **25,000** |

---

## Related

- [Solana CU documentation](https://docs.solana.com/developing/programming-model/runtime#compute-budget) — partial execution on overrun behavior
- [Light Protocol issue #1847](https://github.com/Lightprotocol/light-protocol/issues/1847) — the v0.9.2 CU increase that started this
- Benchmark data with raw slot logs: [`benchmarks/zk-compression.md`](../benchmarks/zk-compression.md)
