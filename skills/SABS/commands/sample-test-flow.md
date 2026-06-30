# Sample Test Flow for This Skill

## Test 1: Program Upgrade
1. Run `./commands/safe-upgrade.sh ... --dry-run`
2. Verify simulation output.
3. Agent should refuse mainnet without human "yes".

## Test 2: ZK Compression Migration
1. Deploy test program with regular accounts.
2. Run migration flow via agent.
3. Check rent reduction and proof verification success.
4. Confirm CU usage < 1.4M per tx.

## Test 3: Cross-Domain
- Upgrade program → migrate state to compressed accounts.
- Agent should link `upgrade-lifecycle.md` → `zk-compression.md`.

**Expected Agent Behavior**: Always shows simulation results, CU estimate, and asks for confirmation.
