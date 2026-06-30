# Governance Action Skill

**Version**: 1.2 (June 2026)  
**Scope**: On-chain governance via Realms (SPL Governance), proposal simulation, and security council integration.

---

## Overview

On-chain governance on Solana in 2026 primarily runs through **SPL Governance** (Realms). Key concepts:

- **Realm**: A DAO. Has a community mint (voting token) and optional council mint (security council).
- **Proposal**: A transaction bundle that can be voted on and executed if it passes.
- **Security Council**: A set of council token holders who can veto proposals within a veto window.
- **Plugin**: Governance plugins extend voting power (e.g., staking derivatives, NFT voting).

---

## Fetching and Parsing a Proposal

```typescript
import { getGovernanceProgramVersion, getAllProposals, withVoteRecord }
  from "@solana/spl-governance";
import { Connection, PublicKey } from "@solana/web3.js";

const REALMS_PROGRAM_ID = new PublicKey("GovER5Lthms3bLBqWub97yVrMmEogzX7xNjdXpPPCVZw");

const connection = new Connection("https://api.mainnet-beta.solana.com");
const realmPk = new PublicKey("YOUR_REALM_ADDRESS");

// Fetch all proposals for a governance account
const proposals = await getAllProposals(
  connection,
  REALMS_PROGRAM_ID,
  realmPk
);

// Filter to active proposals only
const activeProposals = proposals
  .flatMap(p => p)
  .filter(p => p.account.state === "Voting");

for (const proposal of activeProposals) {
  console.log({
    name: proposal.account.name,
    description: proposal.account.descriptionLink,
    yesVotes: proposal.account.yesVotesCount.toNumber(),
    noVotes:  proposal.account.noVotesCount.toNumber(),
    vetoVotes: proposal.account.vetoVotesCount?.toNumber() ?? 0,
    votingEndsAt: new Date(
      proposal.account.votingCompletedAt?.toNumber() ?? 0 * 1000
    ).toISOString(),
  });
}
```

---

## Simulating Proposal Effects Locally

Before voting, simulate what the proposal will actually do if executed.

```typescript
import { getInstructionDataFromBase58 } from "@solana/spl-governance";

// Fetch instruction data from proposal
const proposalInstructions = await getProposalInstructions(
  connection,
  REALMS_PROGRAM_ID,
  proposal.pubkey
);

// Simulate each instruction against cloned mainnet state
for (const ix of proposalInstructions) {
  const { instruction } = ix.account;

  const simulationResult = await connection.simulateTransaction(
    new Transaction().add(instruction),
    [payer],
    true  // replaceRecentBlockhash
  );

  if (simulationResult.value.err) {
    console.error("❌ Proposal instruction simulation FAILED:", {
      instruction: ix.pubkey.toBase58(),
      error: simulationResult.value.err,
      logs: simulationResult.value.logs,
    });
  } else {
    console.log("✅ Simulation passed. CU consumed:", simulationResult.value.unitsConsumed);
  }
}
```

### What to Look For in Simulation

1. **Program upgrade proposals**: Does the buffer match the expected binary hash?
2. **Treasury transfer proposals**: Is the amount and destination correct?
3. **Parameter change proposals**: What accounts does it modify? Is the new value sane?
4. **Malicious proposals**: Does it touch program upgrade authorities unexpectedly? Does it drain a vault?

---

## Generating a Voter Summary

```typescript
function generateVoterSummary(proposal: ProgramAccount<Proposal>): string {
  const totalVotes = proposal.account.yesVotesCount.toNumber()
    + proposal.account.noVotesCount.toNumber();
  const approvalRate = totalVotes > 0
    ? (proposal.account.yesVotesCount.toNumber() / totalVotes * 100).toFixed(1)
    : "0";
  const quorumMet = proposal.account.yesVotesCount.toNumber()
    >= proposal.account.maxVoteWeight?.toNumber()! * 0.1; // example 10% quorum

  return `
## Proposal: ${proposal.account.name}

**Status**: ${proposal.account.state}
**Approval**: ${approvalRate}% (${proposal.account.yesVotesCount} YES / ${proposal.account.noVotesCount} NO)
**Quorum**: ${quorumMet ? "✅ Met" : "❌ Not yet met"}
**Veto votes**: ${proposal.account.vetoVotesCount ?? 0}
**Voting ends**: ${new Date(proposal.account.votingCompletedAt?.toNumber()! * 1000).toUTCString()}

### Simulation Result
Run \`./simulate-proposal.ts ${proposal.pubkey}\` for full instruction-level simulation.
`;
}
```

---

## Security Council Veto Flow

The security council can veto a proposal that has passed community voting but hasn't been executed yet. This window is typically 3–7 days.

```typescript
import { withVetoproposal } from "@solana/spl-governance";

// Check if proposal is in veto window
const isInVetoWindow = (proposal: ProgramAccount<Proposal>): boolean => {
  const now = Date.now() / 1000;
  const votingEndTime = proposal.account.votingCompletedAt?.toNumber() ?? 0;
  const VETO_WINDOW_SECONDS = 3 * 24 * 3600; // 3 days

  return (
    proposal.account.state === "Succeeded" &&
    now < votingEndTime + VETO_WINDOW_SECONDS
  );
};

// Cast veto (requires council token)
async function vetoProposal(proposal: PublicKey, councilMember: Keypair) {
  const ix = await withVetoProposal(
    [],
    REALMS_PROGRAM_ID,
    await getGovernanceProgramVersion(connection, REALMS_PROGRAM_ID),
    realmPk,
    proposal,
    councilMember.publicKey,
    councilMember.publicKey,
    councilTokenAccount,
  );
  // ...sign and send
}
```

---

## Voting Participation Best Practices

- **Low participation**: Add a detailed impact summary to the proposal description. Proposals with "see forum post" descriptions get 2× lower turnout than those with inline summaries.
- **Malicious proposals**: Any proposal that touches program upgrade authorities or moves > 10% of treasury should require bytecode-level simulation before your security council endorses it.
- **Time zone fairness**: Voting windows < 48h disproportionately exclude voters in Asia/Pacific. Realms supports 5-day minimum voting windows — use them.

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **Voting without simulation** | Pass a broken or malicious proposal | Always run instruction simulation before voting |
| **Short voting window** | Low quorum, governance capture risk | Set minimum 5-day voting windows |
| **No veto window** | Security council can't respond to rushed malicious proposals | Configure 3+ day veto window in realm settings |
| **Council too small** | Single council member can block all proposals | Minimum 5 council members, majority veto threshold |

---

## Cross-links
- Program upgrade proposals: [`upgrade-lifecycle.md`](./upgrade-lifecycle.md)
- Treasury vault management: [`institutional-defi.md`](./institutional-defi.md)
- Emergency pause via governance: [`disaster-recovery.md`](./disaster-recovery.md)
