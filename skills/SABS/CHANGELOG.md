# Changelog

All notable changes to SABS are documented here.  
Format: [Semantic Versioning](https://semver.org/). Dates are UTC.

---

## [1.2.0] — 2026-06-30

### Added
- `gotchas/` directory with four real failure post-mortems:
  - Light SDK tree size defaults and rent loss
  - Squads v3 → v4 silent breaking change in proposal format
  - Helius proof staleness window edge cases
  - CU budget overruns under validator load
- `benchmarks/` directory with measured CU costs from devnet runs
- Devnet transaction signatures and real CU measurements in `zk-compression.md`, `upgrade-lifecycle.md`, `web3-privacy-payments.md`
- Runnable test fixtures in `tests/` (Anchor + `solana-test-validator`)
- `.squads.json.example` for project-level multisig config
- Kaveh persona in `agents/advanced-copilot.md` — opinionated, failure-aware

### Changed
- `commands/safe-upgrade.sh`: now reads `.squads.json`, generates real Squads v4 proposal, pipes buffer checksum to comparison
- `commands/zk-migrate.sh`: now functional — batch compression with Helius DAS polling and Light SDK proof generation
- `skill/institutional-defi.md`: expanded from 18 to 80+ lines — Fireblocks policy engine, NAV reporting, Travel Rule hooks
- `skill/ai-agent-oracle.md`: expanded — SP1 proof lifecycle, Switchboard custom feed setup, freshness windows
- `skill/cross-chain-intents.md`: expanded — Mayan route scoring, CCTP burn/mint lifecycle, slippage guard
- `skill/governance-action.md`: expanded — Realms proposal simulation, security council veto flow
- `skill/disaster-recovery.md`: expanded — Helius alert webhooks, pre-staged emergency Squads proposal pattern
- `README.md`: Fixed `YOURUSERNAME` placeholder, added badges, test commands, benchmark table

### Fixed
- `README.md` had a placeholder `YOURUSERNAME` in the clone URL — replaced with `kephothoM/SABS`

---

## [1.1.0] — 2026-06-15

### Added
- `web3-privacy-payments.md` skill: x402 agent payment flow + confidential transfer workflow
- `skill/SKILL.md` routing table: 9 intent categories with keyword matching
- `rules/safety.rules`: 8 rules, 6 hard-enforced (R001–R004, R006, see file)
- `commands/safe-upgrade.sh`: initial dry-run simulation script

### Changed
- `upgrade-lifecycle.md`: added Squads v4 signing flow (previously was generic multi-sig)
- `zk-compression.md`: updated CU estimates — Groth16 verify jumped from ~100k to ~214k CU after Light Protocol v0.9.2 update ([light-protocol#1847](https://github.com/Lightprotocol/light-protocol/issues/1847))

### Why the CU jump matters
We were running upgrade proposals that included a ZK verify step in the same transaction. After the Light Protocol v0.9.2 change, we started hitting compute budget exceeded errors on devnet. Lesson: never share a budget between BPF upgrade instructions and ZK verify in one tx. They're now always split.

---

## [1.0.0] — 2026-06-01

### Initial Release
- Core skill hub with 9 modules: upgrade, ZK compression, mobile, institutional, governance, cross-chain, AI oracle, privacy payments, disaster recovery
- Master router in `skill/SKILL.md`
- Agent persona in `agents/advanced-copilot.md`
- Safety rules in `rules/safety.rules`
- Basic helper scripts: `safe-upgrade.sh`, `zk-migrate.sh`

### Known Issues at Launch
- `safe-upgrade.sh` used a placeholder `squads-cli propose ...` line — not functional (fixed in 1.2.0)
- `zk-migrate.sh` was essentially a stub — only printed advice (fixed in 1.2.0)
- No test fixtures — described tests but provided nothing runnable (fixed in 1.2.0)
- CU estimates in `zk-compression.md` were sourced from pre-v0.9 Light Protocol docs and were too low
