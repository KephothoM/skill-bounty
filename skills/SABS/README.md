# Solana Advanced Builder Skill (SABS)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Solana](https://img.shields.io/badge/Solana-2026%20Stack-9945FF?logo=solana)](https://solana.com)
[![Squads v4](https://img.shields.io/badge/Squads-v4-blue)](https://squads.so)
[![Light Protocol](https://img.shields.io/badge/Light%20Protocol-ZK%20Compression-green)](https://lightprotocol.com)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen)](#running-tests)

**Production-grade AI skill hub** for the Solana AI Kit. Handles safe multi-sig program upgrades (Squads v4), ZK Compression migrations (Helius + Light), mobile flows, institutional DeFi, governance, cross-chain intents, AI oracles, and disaster recovery — with hard safety gates at every mainnet boundary.

> Built after burning real SOL on devnet. Every workflow in this repo has been executed and the receipts are in [`benchmarks/`](./benchmarks/).

---

## Problems Solved

| Problem                                                | Solution                                                                |
| ------------------------------------------------------ | ----------------------------------------------------------------------- |
| Error-prone program upgrades with single-sig           | Squads v4 multi-sig with simulation gate                                |
| Expensive on-chain state at scale                      | ZK Compression: 100x–5000x rent savings (benchmarked)                   |
| Fragmented advanced workflows in the 2026 Solana stack | Progressive routing — only loads relevant context                       |
| Runaway CU costs on ZK operations                      | Pre-profiled CU budgets per operation in [`benchmarks/`](./benchmarks/) |
| No playbook for when things go wrong                   | Real failure stories in [`gotchas/`](./gotchas/)                        |

---

## Features

- **Progressive, token-efficient loading** via master router (`skill/SKILL.md`)
- **Safety rules with hard enforcement** — simulation required, human go/no-go for mainnet (see [`rules/safety.rules`](./rules/safety.rules))
- **Real devnet receipts** — tx signatures and CU measurements in each skill file
- **Failure-first docs** — `gotchas/` covers the non-obvious bugs we actually hit
- **Runnable test fixtures** — Anchor tests + `solana-test-validator` scripts in `tests/`
- **2026 stack** — Squads v4, Helius ZK, Light Protocol v0.10+, Anchor 0.31

---

## Installation

```bash
git clone https://github.com/kephothoM/skill-bounty.git
cd SABS
chmod +x install.sh
./install.sh
```

Configure your environment:

```bash
cp .squads.json.example .squads.json
# Edit .squads.json with your multisig PDA and RPC endpoint
```

---

## Running Tests

Testing smart contracts and instruction generation on Solana can be a headache, so we've made our test suite run instantly offline. It checks the exact instruction shapes your AI generates against the real Squads V4 and Light Protocol SDKs without needing a brittle local validator.

**Prerequisites:** You'll need `node >= 20` and `pnpm`.

> [!WARNING]
> **Windows Users:** You **must** use WSL (Windows Subsystem for Linux) to run this testing environment! The Solana toolchain and associated cryptography packages heavily rely on native Rust compilation and C bindings that will consistently fail or throw weird `ENOENT` errors on native Windows Command Prompt or PowerShell. Just boot up Ubuntu on WSL, clone the repo there, and you're good to go!

```bash
# First, install the necessary dependencies
cd tests && pnpm install

# Run all test suites
# (This tests both the Squads V4 upgrade proposals and ZK Compression offline)
bash ./run-all.sh localnet

# Want to run a specific test suite?
pnpm run test:upgrade
pnpm run test:zk
```

For a deeper dive into how the test environment mocks these complex protocols, check out [`tests/README.md`](./tests/README.md).

---

## Usage

Ask your agent (via Solana AI Kit):

```
"Migrate my token accounts to ZK compression safely"
→ Routes to: zk-compression.md

"Coordinate a Squads v4 multi-sig program upgrade"
→ Routes to: upgrade-lifecycle.md

"Design a cross-chain intent flow with Mayan + CCTP"
→ Routes to: cross-chain-intents.md

"Our program is acting weird on mainnet, help"
→ Routes to: disaster-recovery.md
```

---

## Commands

| Script                                                   | Purpose                                                              |
| -------------------------------------------------------- | -------------------------------------------------------------------- |
| [`commands/safe-upgrade.sh`](./commands/safe-upgrade.sh) | Full Squads v4 proposal generation with buffer checksum verification |
| [`commands/zk-migrate.sh`](./commands/zk-migrate.sh)     | Batch ZK compression migration with proof verification               |

---

## Benchmarks

Real CU and cost measurements from devnet runs: [`benchmarks/`](./benchmarks/)

| Operation                  | CU Used    | Cost (devnet) | Date       |
| -------------------------- | ---------- | ------------- | ---------- |
| Compress 1k accounts       | 847,200 CU | ~$0.0003      | 2026-06-15 |
| Groth16 proof verify       | 214,000 CU | ~$0.00008     | 2026-06-15 |
| Squads v4 upgrade proposal | 18,400 CU  | ~$0.000007    | 2026-06-20 |

---

## Gotchas

Real failure stories so you don't repeat them: [`gotchas/`](./gotchas/)

- [Light SDK tree size defaults will burn your rent](./gotchas/light-sdk-tree-size.md) — ~$2 lost
- [Squads v3 → v4 proposal format is a silent breaking change](./gotchas/squads-v3-to-v4-migration.md)
- [Helius proof staleness window is shorter than you think](./gotchas/helius-proof-staleness.md)
- [CU budget overruns on ZK ops in high-load conditions](./gotchas/cu-budget-overruns.md)

---

## Skill Map

| Skill              | Triggers                                | File                                                           |
| ------------------ | --------------------------------------- | -------------------------------------------------------------- |
| Program Upgrade    | upgrade, multi-sig, Squads, buffer      | [`upgrade-lifecycle.md`](./skill/upgrade-lifecycle.md)         |
| ZK Compression     | compression, Light, Helius, compressed  | [`zk-compression.md`](./skill/zk-compression.md)               |
| Solana Mobile      | mobile, Saga, MWA, React Native         | [`solana-mobile.md`](./skill/solana-mobile.md)                 |
| Institutional DeFi | custody, compliance, NAV                | [`institutional-defi.md`](./skill/institutional-defi.md)       |
| Governance         | Realms, proposal, DAO                   | [`governance-action.md`](./skill/governance-action.md)         |
| Cross-Chain        | intents, bridge, CCTP                   | [`cross-chain-intents.md`](./skill/cross-chain-intents.md)     |
| AI Oracle          | verifiable compute, Switchboard, Ritual | [`ai-agent-oracle.md`](./skill/ai-agent-oracle.md)             |
| Privacy Payments   | x402, shielded, confidential            | [`web3-privacy-payments.md`](./skill/web3-privacy-payments.md) |
| Disaster Recovery  | incident, pause, rollback               | [`disaster-recovery.md`](./skill/disaster-recovery.md)         |

---

## Contributing

PRs welcome. Before submitting a skill update:

1. Run the relevant test suite (`./tests/run-all.sh`)
2. Include at least one devnet tx signature proving the workflow works
3. If you hit a new failure mode, add it to `gotchas/`

---

## License

MIT — see [LICENSE](./LICENSE)
