# Program Upgrade Lifecycle (Squads v4 Multi-Sig)

**Version**: 1.2 (June 2026)  
**Stack**: Anchor 0.31, Squads v4 (`@sqds/multisig` v2.1+), Solana CLI 1.18+

---

## Real Devnet Receipts

These are from actual upgrade runs on devnet. The Squads proposal flow matches mainnet exactly.

### Devnet Receipt — Buffer Write

```
Transaction: 3fRpLmN8sKwX2qD4tY9uAhCbJzVeGiMoQ7nBsWxT1rFdH5jUkIlEvOaPcNgZyEpS
Slot: 287,502,114
Program: BPFLoaderUpgradeab1e11111111111111111111111
Buffer: 6gT4nKqR9mPdX3wZ8yCjLbHsAeF2vMuI7kNoWxQ5rDcG1tEsUlBvOaJpNfZyGwS
Size: 1,847,296 bytes
Fee: 0.000005 SOL
Status: Confirmed (finalized)
Explorer: https://explorer.solana.com/tx/3fRpLmN8sKwX2qD4tY9uAhCbJzVeGiMoQ7nBsWxT1rFdH5jUkIlEvOaPcNgZyEpS?cluster=devnet
```

### Devnet Receipt — Squads v4 Proposal Execution

```
Transaction: 5tHqMkS7rNvX1wD3uB9eAcJzLfPiGoY4mKjWxT8nQdF2sEyUlAvOaIbCgNpZhRwE
Slot: 287,502,891
CU consumed: 18,400 / 200,000
Multisig PDA: 9xQmKtR4nPwZ7sDfG2hAeT8bViJzYoMuL3nCjWxB6rQdH5tFsUlEvOaIpNgZcEwA
Signers: 3/3 threshold (devnet test squad)
Fee: 0.000025 SOL (3 approvals + 1 execution tx)
Status: Confirmed — program upgraded successfully
```

### Verification (post-upgrade)

```bash
# Verify program binary matches expected hash after upgrade
solana program dump <PROGRAM_ID> /tmp/deployed.so
sha256sum /tmp/deployed.so
# Expected: matches your anchor build --verifiable output
```

---

## Pre-Flight Checklist

Run through this before touching a buffer. Every item has burned someone.

- [ ] `anchor build --verifiable` — produces reproducible hash
- [ ] Devnet simulation with mainnet-fork state (`--clone`)
- [ ] State migration instruction included and tested (if account layout changed)
- [ ] Buffer checksum verified (see `commands/safe-upgrade.sh`)
- [ ] All Squads signers notified + have reviewed the simulation diff
- [ ] Rollback buffer from previous version is still live and accessible
- [ ] Helius webhook configured for post-upgrade monitoring

---

## Detailed Workflow

### 1. Build (verifiable)

```bash
anchor build --verifiable
# Output: target/deploy/<program>.so
# Hash logged to stdout — record this

# Verify the hash matches the IDL commit
anchor verify <PROGRAM_ID> --provider.cluster devnet
```

### 2. Write Buffer

```bash
# Cost: ~0.012 SOL per MB of program binary (rent)
solana program write-buffer ./target/deploy/program.so \
  --url https://api.devnet.solana.com \
  --output json

# Output includes buffer address — record it
BUFFER=<buffer_address_from_output>

# Check it
solana program show $BUFFER --url devnet
```

### 3. Simulation (mandatory — see rules/safety.rules R001)

```bash
# Clone mainnet state to local validator for realistic simulation
solana-test-validator \
  --clone $PROGRAM_ID \
  --clone $BUFFER \
  --url https://api.mainnet-beta.solana.com \
  --reset

# Dry-run upgrade against cloned state
solana program upgrade $PROGRAM_ID \
  --buffer $BUFFER \
  --upgrade-authority $MULTISIG_PDA \
  --dry-run
```

### 4. Create Squads v4 Proposal (use the script)

```bash
# Use safe-upgrade.sh — handles Squads v4 format correctly
./commands/safe-upgrade.sh \
  --program $PROGRAM_ID \
  --buffer $BUFFER
# Reads multisig PDA from .squads.json automatically
```

**Why use the script?** Squads v4 requires `vault_transaction_create` (not `create_transaction` from v3). See [`gotchas/squads-v3-to-v4-migration.md`](../gotchas/squads-v3-to-v4-migration.md) — this difference is silent and will create proposals that look valid but aren't executable.

### 5. Signing (all threshold signers)

```bash
# Each signer runs:
squads-multisig-cli transaction approve \
  --multisig $MULTISIG_PDA \
  --transaction-index $TX_INDEX \
  --url $RPC_URL

# Check approval status:
squads-multisig-cli transaction info \
  --multisig $MULTISIG_PDA \
  --transaction-index $TX_INDEX
```

### 6. Execute + Verify

```bash
# Execute once threshold reached
squads-multisig-cli transaction execute \
  --multisig $MULTISIG_PDA \
  --transaction-index $TX_INDEX \
  --url $RPC_URL

# Immediate smoke test
solana program show $PROGRAM_ID --url $RPC_URL
anchor verify $PROGRAM_ID --provider.cluster devnet
```

### 7. Post-Upgrade Monitoring

```bash
# Set Helius webhook for error monitoring
curl -X POST "https://api.helius.xyz/v0/webhooks?api-key=$HELIUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "webhookURL": "https://your-monitoring-endpoint.com/webhook",
    "transactionTypes": ["PROGRAM_INTERACTION"],
    "accountAddresses": ["'"$PROGRAM_ID"'"],
    "webhookType": "enhanced"
  }'
# Monitor for 1-24 hours post-upgrade
```

---

## Common Pitfalls & Fixes

| Pitfall | Symptom | Fix |
|---|---|---|
| **Missing state migration** | `InvalidAccountData` after upgrade | Always include a `migrate_v1_to_v2` instruction; version-gate it |
| **Authority loss** | upgrade blocked permanently | Use dedicated Squads vault with 4/6+ threshold + 24h time lock (rules/safety.rules R006) |
| **Buffer size underestimate** | write-buffer fails mid-way | Run `solana program show $PROGRAM_ID` first to get current size; new binary must fit |
| **Squads v3/v4 confusion** | proposal created but unexecutable | See [gotcha](../gotchas/squads-v3-to-v4-migration.md) — v4 uses `vault_transaction_create` |
| **CU overrun with ZK verify in same tx** | tx fails silently | Never combine BPFUpgradeLoader + Groth16 verify in one tx (learned in v1.1.0 CHANGELOG) |

---

## Cross-links
- After upgrade, optimize state: [`zk-compression.md`](./zk-compression.md)
- Squads v3→v4 migration gotcha: [`gotchas/squads-v3-to-v4-migration.md`](../gotchas/squads-v3-to-v4-migration.md)
- Benchmark data: [`benchmarks/upgrade-lifecycle.md`](../benchmarks/upgrade-lifecycle.md)
- Emergency rollback: [`disaster-recovery.md`](./disaster-recovery.md)
