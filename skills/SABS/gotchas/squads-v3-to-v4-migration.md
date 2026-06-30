# Gotcha: Squads v3 → v4 Proposal Format Is a Silent Breaking Change

**Date**: April 2026  
**Severity**: High — two mainnet upgrades executed without proper multi-sig review  
**Skill**: [`upgrade-lifecycle.md`](../skill/upgrade-lifecycle.md)  
**Squads SDK versions**: v3 (`@sqds/sdk` ≤ 0.2.x) → v4 (`@sqds/multisig` ≥ 1.0.0)

---

## What Happened

We migrated our Squads multisig from v3 to v4 (the new on-chain program at `SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf`). The migration went smoothly. The problem came afterward.

Our CI pipeline had a health check step that verified "is there a pending upgrade proposal that hasn't been executed yet?" This was used as a gate — if a proposal existed, the pipeline would pause and wait for human signers.

The check used the old v3 SDK:

```typescript
// OLD CI CHECK (Squads v3 SDK — BROKEN after v4 migration)
import { Squads } from "@sqds/sdk";

const squads = Squads.devnet(wallet);
const tx = await squads.getTransaction(proposalPDA);
// tx is null if no v3 transaction exists → CI interpreted as "no pending proposal"
```

After migrating to Squads v4, `getTransaction` from the v3 SDK returns `null` for *all* proposals — because v4 proposals are stored under a completely different account structure. The CI check was always seeing `null` and proceeding.

**Result**: We deployed twice to mainnet without the expected 3/3 signer review. The proposals were created correctly (we had updated the proposal creation code), but the *status check* was broken. We only caught it after the second deployment when a signer mentioned they hadn't received a notification.

---

## The Non-Obvious Part

The v3 and v4 programs are different program IDs. When you migrate your *multisig account*, you're not migrating your *SDK calls*. Every SDK call site needs to be audited:

| SDK Call | v3 (`@sqds/sdk`) | v4 (`@sqds/multisig`) |
|---|---|---|
| Create proposal | `squads.createTransaction(...)` | `multisig.vaultTransactionCreate(...)` |
| Approve | `squads.approveTransaction(...)` | `multisig.proposalApprove(...)` |
| Execute | `squads.executeTransaction(...)` | `multisig.vaultTransactionExecute(...)` |
| **Get proposal** | `squads.getTransaction(PDA)` | `multisig.getProposal(multisigPda, index)` |
| **Get status** | `tx.status.active !== undefined` | `proposal.status.__kind === 'Active'` |

The status field shape is completely different. v3 uses `{ active: {} }` (Anchor-style enum object). v4 uses `{ __kind: 'Active' }` (different enum serialization). If you're checking `tx.status.active` and the proposal is `null`, your code continues silently.

---

## The Fix

**Audit every Squads SDK call site.** Don't assume "the proposal creation code was updated" means "all Squads code was updated."

```typescript
// ✅ CORRECT: Squads v4 proposal status check
import { getProposal } from "@sqds/multisig";

async function hasPendingProposal(
  connection: Connection,
  multisigPda: PublicKey,
  transactionIndex: bigint
): Promise<boolean> {
  try {
    const [proposalPda] = multisig.getProposalPda({
      multisigPda,
      transactionIndex,
    });
    const proposal = await getProposal(connection, proposalPda);

    // v4 enum: 'Draft' | 'Active' | 'Rejected' | 'Approved' | 'Executing' | 'Executed' | 'Cancelled'
    return proposal.status.__kind === "Active" || proposal.status.__kind === "Approved";
  } catch (e) {
    // Account not found = no proposal at this index
    return false;
  }
}
```

**Add a version assertion to your CI:**

```typescript
// At the top of any Squads-related script
import { PROGRAM_ID as SQUADS_V4_PROGRAM_ID } from "@sqds/multisig";

async function assertSquadsV4(multisigPda: PublicKey) {
  const multisigAccount = await connection.getAccountInfo(multisigPda);
  if (!multisigAccount?.owner.equals(SQUADS_V4_PROGRAM_ID)) {
    throw new Error(
      `Multisig ${multisigPda} is not owned by Squads v4 program. ` +
      `Owner: ${multisigAccount?.owner}. ` +
      `Did you migrate but forget to update the SDK?`
    );
  }
}
```

---

## Migration Audit Checklist

When migrating from Squads v3 to v4:

- [ ] Search entire codebase for `@sqds/sdk` imports → replace with `@sqds/multisig`
- [ ] Search for `getTransaction` → replace with `getProposal`
- [ ] Search for `.status.active` → replace with `.status.__kind === 'Active'`
- [ ] Search for `createTransaction` → replace with `vaultTransactionCreate`
- [ ] Search for `approveTransaction` → replace with `proposalApprove`
- [ ] Search for `executeTransaction` → replace with `vaultTransactionExecute`
- [ ] Test proposal creation, status check, and execution against devnet before touching mainnet
- [ ] Add `assertSquadsV4` assertion at entry point of every CI gate

---

## Related Resources

- [Squads v4 migration guide](https://docs.squads.so/squads-v4/migration) — official, but doesn't call out the silent `null` behavior
- [Squads v4 SDK changelog](https://github.com/Squads-Protocol/v4/blob/main/CHANGELOG.md) — search for `getProposal` to see the API change
- The `commands/safe-upgrade.sh` script in this repo uses the v4 CLI exclusively and asserts the multisig program ID
