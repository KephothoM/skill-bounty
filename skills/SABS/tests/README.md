# Tests — SABS

## Overview

This directory contains runnable tests for SABS workflows. Tests use:
- **Anchor test framework** (`anchor test`) for on-chain program behavior
- **`solana-test-validator`** for local validator with cloned state
- **`@lightprotocol/stateless.js`** for ZK compression operations
- **`@sqds/multisig`** for Squads v4 proposal simulation

---

## Prerequisites

```bash
# Required tools
solana --version        # >= 1.18
anchor --version        # >= 0.31.0
node --version          # >= 20
pnpm --version          # >= 8

# Install test dependencies
cd tests && pnpm install
```

---

## Environment Setup

```bash
# Set Solana to devnet (or localnet for isolated testing)
solana config set --url devnet

# Generate a test keypair (save it — you'll need it for fixtures)
solana-keygen new -o ./fixtures/test-keypair.json --no-bip39-passphrase

# Airdrop SOL for test fees (devnet only)
solana airdrop 5 --keypair ./fixtures/test-keypair.json

# Set your Helius API key for compression tests
export HELIUS_API_KEY=your_devnet_api_key_here
```

---

## Running Tests

```bash
# All tests (starts local validator automatically)
./run-all.sh

# Individual suites
anchor test tests/upgrade/upgrade.test.ts
anchor test tests/zk/compression.test.ts

# With verbose output
RUST_LOG=solana_runtime::system_instruction_processor=trace \
  anchor test tests/zk/compression.test.ts
```

---

## Test Suites

| Suite | File | What It Tests |
|---|---|---|
| Program Upgrade | `upgrade/upgrade.test.ts` | Squads v4 proposal → approval → execution lifecycle |
| ZK Compression | `zk/compression.test.ts` | Batch compression, proof verify, account reads |

---

## Fixtures

| File | Description |
|---|---|
| `fixtures/devnet-accounts.json` | Known devnet accounts for integration tests |
| `fixtures/test-keypair.json` | Test wallet (do NOT use on mainnet) |
| `fixtures/test-program.so` | Pre-compiled test program binary |

---

## Expected Output

```
$ ./run-all.sh

SABS Test Suite — 2 suites, 8 tests
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
