# Advanced Builder Overview

**Version**: 1.2 (June 2026)

SABS is a production-grade AI skill hub for the 2026 Solana stack. It covers the 9 highest-risk / highest-complexity domains where "just read the docs" isn't enough.

---

## When SABS Activates

Any non-trivial task involving: program upgrades, ZK state scaling, mobile signing, institutional custody, DAO governance, cross-chain intents, verifiable AI compute, private payments, or incident response.

If it touches mainnet capital and could go wrong in a way that requires a 3am phone call — SABS has a playbook for it.

---

## Skill Synergies (Common Multi-Step Flows)

### Flow 1: Launch + Scale

```
anchor build --verifiable
  → upgrade-lifecycle.md    (Squads v4 multi-sig upgrade)
  → zk-compression.md       (compress state for 100x–5000x rent savings)
  → benchmarks/             (validate CU budgets before mainnet)
```

### Flow 2: Institutional Vault

```
institutional-defi.md       (Fireblocks policy engine, segmented vaults)
  → web3-privacy-payments.md (confidential state transitions)
  → cross-chain-intents.md   (USDC rebalancing via CCTP or Mayan)
  → governance-action.md     (DAO-controlled vault parameters)
```

### Flow 3: Production Incident

```
disaster-recovery.md        (Helius anomaly detection → emergency pause)
  → upgrade-lifecycle.md    (rollback to previous buffer)
  → governance-action.md    (community vote on post-mortem changes)
```

### Flow 4: Verifiable AI Agent

```
ai-agent-oracle.md          (SP1 zkVM proof of inference result)
  → web3-privacy-payments.md (x402 agent-to-agent micropayment)
  → zk-compression.md        (compressed storage of agent state)
```

---

## Non-Negotiable Principles

These apply across all skills:

1. **Simulate before mainnet** — always (rules/safety.rules R001)
2. **Human go/no-go at mainnet boundary** — always (rules/safety.rules R002)
3. **Multi-sig for all upgrade authorities** — 3/5 minimum, 24h time lock (rules/safety.rules R006)
4. **Verify ZK proofs on-chain** — never trust off-chain proof alone (rules/safety.rules R004)
5. **CU limit = 2× measured** — measured on devnet, 2× for mainnet safety (see [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md))

---

## Real Evidence

Every workflow in this repo has been executed. The evidence is in:
- [`benchmarks/`](../benchmarks/) — CU measurements, timing, cost tables
- [`gotchas/`](../gotchas/) — real failure stories with root causes and fixes

The transaction signatures in skill files are from actual devnet runs.
