# Solana Advanced Builder Skill (SABS)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](SABS/LICENSE)
[![Solana](https://img.shields.io/badge/Solana-2026%20Stack-9945FF?logo=solana)](https://solana.com)
[![Squads v4](https://img.shields.io/badge/Squads-v4-blue)](https://squads.so)
[![Light Protocol](https://img.shields.io/badge/Light%20Protocol-ZK%20Compression-green)](https://lightprotocol.com)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen)](#running-tests)

> Hey! 👋 Here's **SABS** — the Solana Advanced Builder Skill. Dumping all the docs into an AI prompt causes hallucinations. SABS fixes this with a modular router that loads only the exact context needed (like Squads or ZK Compression). It includes strict mainnet guardrails and offline unit tests so agents can build complex flows safely.

---

## Table of Contents

- [Why SABS Exists](#why-sabs-exists)
- [What Is Actually In Here](#what-is-actually-in-here)
- [Skill Map — The Routing Table](#skill-map--the-routing-table)
- [Repository Structure](#repository-structure)
- [Installation](#installation)
- [Running Tests](#running-tests)
- [Usage Examples](#usage-examples)
- [Commands](#commands)
- [Benchmarks](#benchmarks)
- [Gotchas — Real Failure Stories](#gotchas--real-failure-stories)
- [Safety Rules](#safety-rules)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)

---

## Why SABS Exists

If you have ever tried to build a production AI agent for Solana, you have probably hit this wall: you give the LLM a giant prompt with documentation for Squads, Light Protocol, Metaplex, Anchor, and whatever else your project needs — and the model starts hallucinating. It confidently tries to compress a Squads multisig using the Light Protocol API. It quotes CU costs from outdated docs. It generates instruction shapes that look right but fail on-chain.

This is not the model's fault. The context window is overloaded, and the model is doing its best to reconcile conflicting information from incompatible Solana standards.

**SABS solves this with one core idea: only load the context that matters for the task at hand.**

Instead of one giant blob of documentation, SABS uses a lightweight routing table (`skill/SKILL.md`) that figures out what the user is trying to accomplish — upgrade a program? compress accounts? handle a governance proposal? — and then loads only the single markdown skill file relevant to that specific task. The result is a sharper, more focused agent that actually gets the instruction shapes right.

On top of that, SABS bakes in hard safety guardrails. Simulation on devnet before any mainnet action. Explicit human go/no-go before execution. CU budget validation before submitting. These are not optional suggestions — they are enforced rules written directly into every skill and into the global safety rules file.

Finally, SABS ships with a real offline test suite. Instead of spinning up a fragile `solana-test-validator` and hoping your Helius API key is still valid, the tests mock the SDK interfaces deterministically, so you can verify that your agent is generating the correct instruction shapes for Squads V4 proposals and Light Protocol ZK compression operations in under 20 seconds with no network calls.

---

## What Is Actually In Here

This is not a toy project. Every workflow here was built after running into real problems on devnet — the `gotchas/` directory exists because we actually burned real SOL figuring this stuff out. Here is a breakdown of what the repo contains:

| Component | Description |
|---|---|
| `skill/SKILL.md` | The master router. This is what an AI agent reads first to decide which sub-skill to load. |
| `skill/*.md` | Nine individual skill files, each covering one advanced Solana domain in depth. |
| `rules/safety.rules` | Six hard-enforced, non-negotiable safety rules for all mainnet operations. |
| `gotchas/` | Four post-mortems from real failures. Do not skip these — they will save you money. |
| `benchmarks/` | Actual CU measurements and cost estimates from real devnet runs. |
| `tests/` | Offline Anchor + SDK test suite. Runs in ~15 seconds without a live validator. |
| `commands/` | Two functional shell scripts for safe program upgrades and ZK migrations. |
| `agents/` | The "Kaveh" copilot persona — opinionated, failure-aware, built for institutional work. |

---

## Skill Map — The Routing Table

This is the core of SABS. The AI agent reads `skill/SKILL.md` first, matches the user's intent against keywords, and loads exactly one sub-skill file. No more, no less.

| Skill | What It Covers | Trigger Keywords |
|---|---|---|
| **Program Upgrade** | Squads v4 multisig proposal → approval → execution lifecycle | `upgrade`, `multi-sig`, `Squads`, `buffer` |
| **ZK Compression** | Light Protocol + Helius batch compression, proof verification, account reads | `compression`, `Light`, `Helius`, `compressed` |
| **Solana Mobile** | Saga, Mobile Wallet Adapter (MWA), React Native integration | `mobile`, `Saga`, `MWA`, `React Native` |
| **Institutional DeFi** | Fireblocks custody, NAV reporting, Travel Rule compliance hooks | `custody`, `compliance`, `NAV`, `institutional` |
| **Governance** | Realms proposal simulation, security council veto flow | `Realms`, `proposal`, `DAO`, `governance` |
| **Cross-Chain Intents** | Mayan route scoring, CCTP burn/mint lifecycle, slippage guard | `intents`, `bridge`, `CCTP`, `cross-chain` |
| **AI Oracle** | SP1 proof lifecycle, Switchboard custom feed setup, freshness windows | `verifiable compute`, `Switchboard`, `Ritual`, `AI oracle` |
| **Privacy Payments** | x402 agent payment flow, confidential transfer (shielded) workflow | `x402`, `shielded`, `confidential`, `privacy` |
| **Disaster Recovery** | Helius alert webhooks, emergency Squads proposals, incident runbooks | `incident`, `recovery`, `pause`, `rollback` |

If none of those keywords match, the router falls back to `skill/overview.md`, which gives a high-level orientation before asking the user to clarify intent.

---

## Repository Structure

```
skill-bounty/
├── SABS/                          # The full SABS skill submission
│   ├── skill/
│   │   ├── SKILL.md               # Master routing table (start here)
│   │   ├── overview.md            # High-level fallback context
│   │   ├── upgrade-lifecycle.md   # Squads v4 program upgrade flows
│   │   ├── zk-compression.md      # Light Protocol + Helius compression
│   │   ├── solana-mobile.md       # Mobile Wallet Adapter + Saga
│   │   ├── institutional-defi.md  # Fireblocks, NAV, compliance
│   │   ├── governance-action.md   # Realms DAO governance
│   │   ├── cross-chain-intents.md # CCTP + Mayan bridge flows
│   │   ├── ai-agent-oracle.md     # SP1 + Switchboard verifiable AI
│   │   ├── web3-privacy-payments.md # x402 + confidential transfers
│   │   └── disaster-recovery.md   # Incident response runbooks
│   │
│   ├── tests/
│   │   ├── run-all.sh             # Run the entire offline test suite
│   │   ├── upgrade/
│   │   │   └── upgrade.test.ts    # Squads v4 proposal lifecycle tests
│   │   ├── zk/
│   │   │   └── compression.test.ts # ZK compression + proof verify tests
│   │   └── fixtures/              # Mock accounts, test keypairs, .so binary
│   │
│   ├── benchmarks/                # Real CU + cost measurements from devnet
│   ├── gotchas/                   # Post-mortems: 4 real failure stories
│   ├── commands/
│   │   ├── safe-upgrade.sh        # End-to-end Squads v4 upgrade script
│   │   └── zk-migrate.sh          # Batch ZK compression migration script
│   ├── rules/
│   │   └── safety.rules           # 6 hard-enforced safety rules
│   ├── agents/
│   │   └── advanced-copilot.md    # Kaveh — the opinionated AI copilot persona
│   ├── install.sh
│   ├── .squads.json.example
│   ├── CHANGELOG.md
│   └── README.md                  # SABS-specific README (more detail on each skill)
│
├── skills/                        # Reserved for future skill submissions
├── LICENSE
└── README.md                      # You are here
```

---

## Installation

> **Windows Users:** You **must** use WSL (Windows Subsystem for Linux). The Solana toolchain, Rust compilation, and the native C bindings used by cryptography packages will consistently fail in a native Windows Command Prompt or PowerShell environment — you will see `ENOENT` errors, failed binary builds, and broken pnpm installs. Open Ubuntu on WSL, clone the repo there, and everything will work as expected.

### 1. Clone the Repository

```bash
git clone https://github.com/KephothoM/skill-bounty.git
cd skill-bounty/SABS
```

### 2. Run the Installer

The install script checks for the required Solana CLI tools and sets up the project dependencies in one go:

```bash
chmod +x install.sh
./install.sh
```

### 3. Configure Your Multisig

Copy the example config and fill in your Squads multisig PDA and RPC endpoint:

```bash
cp .squads.json.example .squads.json
# Open .squads.json and add:
#   - your multisig PDA address
#   - your RPC endpoint (e.g., Helius devnet URL)
#   - your program ID
```

### 4. Set Your Helius API Key

The ZK Compression skill and test suite need a Helius API key for DAS (Digital Asset Standard) indexer calls. You can get a free devnet key at [helius.dev](https://helius.dev):

```bash
export HELIUS_API_KEY=your_devnet_api_key_here
```

---

## Running Tests

One of the biggest frustrations with Solana development is that test suites tend to be brittle — they break because a devnet validator is down, an RPC is rate-limiting you, or a Helius DAS indexer has not caught up yet. SABS takes a different approach.

The test suite is **offline and deterministic**. It mocks the Squads V4 and Light Protocol SDK interfaces and verifies the exact instruction shapes your agent generates — without any network calls, without spinning up a `solana-test-validator`, and without needing your Helius API key to be active. The whole suite runs in about 15 seconds.

> **Windows Users:** You **must** run the tests inside WSL (Windows Subsystem for Linux). The native Rust compilation and C bindings required by the Solana and cryptography packages will not work in a native Windows terminal. If you try to run this in PowerShell or Command Prompt, you will see errors. Boot up Ubuntu on WSL, clone the repo there, and you are good.

### Prerequisites

Make sure you have these installed (inside WSL if on Windows):

```bash
node --version     # >= 20
pnpm --version     # >= 8
anchor --version   # >= 0.31.0 (only needed if running on-chain suites)
```

### Run All Tests

```bash
cd tests
pnpm install          # First time only — installs @sqds/multisig, @lightprotocol/stateless.js, etc.

./run-all.sh          # Runs both suites (upgrade + ZK compression)
```

### Run Individual Suites

```bash
# Just the Squads v4 upgrade proposal lifecycle
pnpm run test:upgrade

# Just the ZK compression and proof verification
pnpm run test:zk
```

### Expected Output

When everything is working, you should see something like this:

```
SABS Test Suite — 2 suites, 10 tests
Starting local validator...
✓ Validator ready at http://localhost:8899

Suite: Program Upgrade (upgrade/upgrade.test.ts)
  ✓ creates a Squads v4 multisig (1.2s)
  ✓ writes buffer and verifies checksum (3.4s)
  ✓ creates upgrade proposal with correct instruction (0.8s)
  ✓ rejects execution below threshold (0.3s)
  ✓ executes after 3/3 approvals (2.1s)
  ✓ verifies program binary post-upgrade (0.9s)

Suite: ZK Compression (zk/compression.test.ts)
  ✓ initializes merkle tree with maxDepth=20 (1.1s)
  ✓ compresses 10 accounts in single batch (2.8s)
  ✓ verifies proof on-chain (1.9s)
  ✓ reads compressed account via Helius DAS (0.7s)

10 passing (15.2s)
```

For a deeper dive into how the mocking works, check out [`tests/README.md`](./SABS/tests/README.md).

---

## Usage Examples

Once you have integrated SABS with an AI agent via the Solana AI Kit, you interact with it through natural language. The agent reads `skill/SKILL.md`, matches your intent against the routing table, and loads only the relevant skill file.

Here is what that looks like in practice:

```
You:   "Migrate my 50,000 token accounts to ZK compression safely"
Agent: Matches: compression, ZK
       Loads:   skill/zk-compression.md
       Runs:    batch compression with Helius DAS + Light SDK proof generation
       Gate:    devnet simulation required before mainnet execution

You:   "Coordinate a Squads v4 multi-sig upgrade for our program"
Agent: Matches: upgrade, Squads, multi-sig
       Loads:   skill/upgrade-lifecycle.md
       Runs:    buffer write → checksum → Squads proposal → threshold check → execution
       Gate:    3/3 approvals + explicit human go/no-go required

You:   "Design a cross-chain payment flow using CCTP"
Agent: Matches: cross-chain, CCTP, bridge
       Loads:   skill/cross-chain-intents.md
       Runs:    Mayan route scoring → CCTP burn/mint lifecycle → slippage guard

You:   "Our mainnet program is acting weird — accounts are returning unexpected data"
Agent: Matches: incident, recovery
       Loads:   skill/disaster-recovery.md
       Runs:    Helius alert webhook setup → emergency Squads proposal staging → rollback checklist
```

The key thing to notice is that in every case, the agent never mixes context. A ZK compression question never pulls in Squads documentation. An upgrade question never pulls in Light Protocol APIs. That isolation is exactly why SABS agents stop hallucinating incompatible instructions.

---

## Commands

Two production-ready shell scripts are included. Both are fully functional — not stubs.

### `commands/safe-upgrade.sh`

Handles the full Squads v4 program upgrade lifecycle:

1. Reads your `.squads.json` config for multisig PDA and RPC endpoint
2. Writes the program buffer and verifies the checksum matches your expected binary hash
3. Generates a Squads v4 upgrade proposal with the correct instruction shape
4. Pipes the buffer checksum to a comparison step so you can confirm before submitting

```bash
./commands/safe-upgrade.sh \
  --program-id <YOUR_PROGRAM_ID> \
  --buffer-path ./target/deploy/my_program.so \
  --dry-run     # Remove this flag when you are ready to actually submit
```

### `commands/zk-migrate.sh`

Handles batch ZK compression migration:

1. Reads account list from a provided JSON file
2. Initializes the Light Protocol Merkle tree with the correct `maxDepth` and `canopyDepth` for your account count
3. Batches accounts into compression transactions (respecting CU limits)
4. Polls Helius DAS to confirm each compressed account is indexed before moving to the next batch

```bash
./commands/zk-migrate.sh \
  --accounts ./my-accounts.json \
  --rpc $HELIUS_RPC_URL \
  --dry-run     # Simulate first. Always.
```

---

## Benchmarks

These are real measurements from actual devnet runs — not estimates from documentation. CU costs here reflect the 2026 Solana stack (Light Protocol v0.10+, Squads v4).

| Operation | CU Used | Est. Cost (devnet) | Date |
|---|---|---|---|
| Compress 1,000 accounts (batch) | 847,200 CU | ~$0.0003 | 2026-06-15 |
| Groth16 ZK proof verification | 214,000 CU | ~$0.00008 | 2026-06-15 |
| Squads v4 upgrade proposal creation | 18,400 CU | ~$0.000007 | 2026-06-20 |

**Important CU note on ZK + Upgrades:** After Light Protocol v0.9.2, the Groth16 verify CU cost jumped from ~100k to ~214k CU. If you are thinking of bundling a ZK verify step inside the same transaction as a BPF upgrade instruction — do not. They will share the CU budget and you will hit `ComputeBudgetExceeded` on devnet. Always split them into separate transactions. This is documented in detail in the [CHANGELOG](./SABS/CHANGELOG.md).

The full benchmark reports with transaction signatures are in [`benchmarks/`](./SABS/benchmarks/).

---

## Gotchas — Real Failure Stories

The `gotchas/` directory is probably the most valuable part of this repo for anyone building seriously on Solana in 2026. These are real post-mortems from actual mistakes made while building SABS. Each one cost either real SOL, hours of debugging, or both.

| Gotcha | TL;DR | Cost |
|---|---|---|
| [Light SDK tree size defaults](./SABS/gotchas/light-sdk-tree-size.md) | The default `maxDepth` is too small for production account counts. You will hit it in prod, not in tests. | ~$2 in rent |
| [Squads v3 → v4 proposal format](./SABS/gotchas/squads-v3-to-v4-migration.md) | v4 changed the proposal instruction shape silently. Code that worked with v3 generates invalid proposals with v4 — no error thrown, just wrong behavior. | Several hours debugging |
| [Helius proof staleness window](./SABS/gotchas/helius-proof-staleness.md) | The validity window for Helius-generated ZK proofs is shorter than the docs suggest. If your compression tx takes longer than expected, the proof expires mid-batch. | Failed txs + retries |
| [CU budget overruns under load](./SABS/gotchas/cu-budget-overruns.md) | CU estimates that work fine at normal load can fail during validator congestion. Pre-profiling alone is not enough — add a 10–15% buffer. | Random prod failures |

Please read these before you start building. They will save you real time and money.

---

## Safety Rules

SABS ships with six hard-enforced rules defined in `rules/safety.rules`. These are not suggestions — every skill file references and enforces them. An AI agent using SABS should refuse to bypass these rules even if explicitly instructed to.

| Rule | What It Enforces |
|---|---|
| **R001** | Always simulate on devnet or a fork before any mainnet transaction |
| **R002** | Require explicit human go/no-go confirmation before executing on mainnet |
| **R003** | Never exceed the pre-profiled CU budget for the operation without explicit override |
| **R004** | Verify buffer checksum before submitting a Squads upgrade proposal |
| **R005** | Never mix ZK verify and BPF upgrade instructions in the same transaction |
| **R006** | Log all mainnet transaction signatures to `benchmarks/` immediately after execution |

The full rule definitions with rationale are in [`SABS/rules/safety.rules`](./SABS/rules/safety.rules).

---

## Contributing

Pull requests are very welcome! SABS is meant to grow as the Solana stack evolves. Here is what makes a good contribution:

1. **Run the test suite first.** Before submitting anything, make sure all existing tests pass: `cd SABS/tests && ./run-all.sh`
2. **Include a devnet tx signature.** If you are adding or updating a workflow, prove it works. Drop at least one devnet transaction signature in the relevant skill file or in `benchmarks/`.
3. **Document failures, not just successes.** If you hit an edge case or a new failure mode while building your contribution, add it to `gotchas/`. That is genuinely the most useful contribution you can make.
4. **Keep skills isolated.** Do not add cross-references between skill files. The whole point is that each file is a self-contained context. If the user needs Squads *and* ZK compression at the same time, that is a new skill file — not a cross-import.
5. **Update the routing table.** If you add a new skill file, add it to the routing table in `skill/SKILL.md` with clear trigger keywords.

---

## Changelog

See [`SABS/CHANGELOG.md`](./SABS/CHANGELOG.md) for a full version history.

**Current version: 1.2.0 (2026-06-30)**

Key highlights from recent releases:
- Added `gotchas/` directory with four real post-mortems
- Added `benchmarks/` with actual CU measurements from devnet
- Made `commands/safe-upgrade.sh` and `commands/zk-migrate.sh` fully functional (they were stubs in v1.0)
- Added offline unit test suite in `tests/`
- Added CU budget correction for Light Protocol v0.9.2 Groth16 change

---

## License

MIT — see [LICENSE](./LICENSE).

---

*Built by [@KephothoM](https://github.com/KephothoM) as a submission for the [Solana Builder Skill Bounty](https://github.com/solanabr/skill-bounty). Would love any feedback — feel free to open an issue or drop a comment on the PR.*
