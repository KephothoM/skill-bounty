# Disaster Recovery Skill

**Version**: 1.2 (June 2026)  
**Scope**: Incident detection, emergency pause, rollback, and post-mortem for Solana programs.

---

## Overview

Disaster recovery on Solana has one constraint that doesn't exist in web2: **you cannot stop the chain**. If your program is processing malicious transactions, they will keep arriving while you prepare a response. Your recovery plan must be designed for this reality.

Key principle: **pre-stage everything**. Emergency proposals, pause instructions, and rollback buffers should all be prepared and tested *before* you need them.

---

## Step 1: Anomaly Detection (Helius Webhooks)

Set up monitoring before you deploy, not after something goes wrong.

```typescript
// Set up a Helius webhook on your program address
const webhookConfig = {
  webhookURL: "https://your-pagerduty-or-slack-endpoint.com/incident",
  transactionTypes: ["PROGRAM_INTERACTION"],
  accountAddresses: [PROGRAM_ID.toBase58()],
  webhookType: "enhanced",
  txnStatus: "all",   // capture BOTH success and failure
};

const response = await fetch(
  `https://api.helius.xyz/v0/webhooks?api-key=${HELIUS_API_KEY}`,
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(webhookConfig),
  }
);

// Add alert rules to your webhook handler
function analyzeTransaction(tx: HeliusTransaction): Alert | null {
  const isHighValue   = tx.nativeTransfers?.some(t => t.amount > 100 * LAMPORTS_PER_SOL);
  const isUnexpectedAccount = tx.accountData?.some(
    a => !EXPECTED_ACCOUNTS.has(a.account)
  );
  const isAbruptStateChange = tx.events?.some(
    e => e.type === "COMPRESSED_NFT_MINT" && e.amount > 1000
  );

  if (isHighValue || isUnexpectedAccount) {
    return {
      severity: "critical",
      message: `Anomaly in program ${PROGRAM_ID}: ${JSON.stringify({ isHighValue, isUnexpectedAccount })}`,
      txSig: tx.signature,
      slot: tx.slot,
    };
  }
  return null;
}
```

---

## Step 2: Emergency Pause

### Option A: Built-in Emergency Flag (recommended)

Include an emergency pause mechanism in your program at deploy time:

```rust
use anchor_lang::prelude::*;

#[account]
pub struct GlobalConfig {
    pub emergency_paused: bool,
    pub pause_authority: Pubkey,    // should be Squads emergency vault
}

#[derive(Accounts)]
pub struct EmergencyPause<'info> {
    #[account(
        mut,
        constraint = config.pause_authority == authority.key() @ ErrorCode::UnauthorizedPause
    )]
    pub config: Account<'info, GlobalConfig>,
    pub authority: Signer<'info>,
}

pub fn emergency_pause(ctx: Context<EmergencyPause>) -> Result<()> {
    ctx.accounts.config.emergency_paused = true;
    msg!("EMERGENCY PAUSE ACTIVATED at slot: {}", Clock::get()?.slot);
    emit!(EmergencyPauseEvent {
        slot: Clock::get()?.slot,
        authority: ctx.accounts.authority.key(),
    });
    Ok(())
}

// In every user-facing instruction, add this guard:
pub fn some_user_instruction(ctx: Context<SomeInstruction>) -> Result<()> {
    require!(!ctx.accounts.config.emergency_paused, ErrorCode::ProgramPaused);
    // ... rest of instruction
    Ok(())
}
```

### Option B: Pre-staged Squads Emergency Proposal

If you can't modify the program (or need a backup), pre-create a Squads proposal that pauses the program. This can be created in advance and activated quickly:

```bash
# Pre-stage emergency proposal (do this BEFORE you need it)
./commands/safe-upgrade.sh \
  --program $PROGRAM_ID \
  --buffer $PREVIOUS_SAFE_BUFFER \  # rollback buffer
  --memo "EMERGENCY: rollback to v1.2 — activate if v1.3 is exploited"
```

Record the proposal PDA. In an emergency, just collect signatures and execute.

---

## Step 3: Rollback

```bash
# Keep the previous working buffer ALWAYS live (rules/safety.rules R007)
# Check it's still valid
solana program show $PREVIOUS_BUFFER --url mainnet-beta

# If emergency pause isn't enough, initiate rollback upgrade via Squads
./commands/safe-upgrade.sh \
  --program $PROGRAM_ID \
  --buffer $PREVIOUS_BUFFER \
  --rpc https://api.mainnet-beta.solana.com
# This creates a new Squads proposal; requires threshold signers
```

**Rollback time estimate**: 5–15 minutes (proposal creation + signer coordination + execution). This assumes you have:
- Previous buffer still live
- All signers available and responsive
- Pre-agreed communication channel (Signal group, not Telegram)

---

## Step 4: Post-Mortem Template

Use this after every incident. File it in `gotchas/` if it reveals a new failure mode.

```markdown
# Post-Mortem: [Incident Name]

**Date**: YYYY-MM-DD  
**Duration**: X hours from detection to resolution  
**Severity**: [P0 / P1 / P2]  
**Affected users**: N  
**Funds at risk**: X SOL  
**Funds actually lost**: Y SOL  

## Timeline
- HH:MM UTC — [event]
- HH:MM UTC — [detection]
- HH:MM UTC — [emergency pause activated]
- HH:MM UTC — [rollback executed]
- HH:MM UTC — [service restored]

## Root Cause
[One sentence: what was the proximate cause?]

## Why It Wasn't Caught Earlier
[The non-obvious part — what should have detected this?]

## What We Did
[Step-by-step recovery actions taken]

## What We Changed
- [Monitoring rule added]
- [Code fix applied]
- [Process changed]

## What We Should Have Had
[What pre-existing tooling/safeguards would have prevented this or shortened recovery?]
```

---

## Pre-Incident Readiness Checklist

Run through this quarterly:

- [ ] Emergency pause instruction deployed and tested on devnet
- [ ] Previous working buffer is still live: `solana program show $BUFFER`
- [ ] All Squads signers have tested the signing flow within last 30 days
- [ ] Helius webhook is active and delivering alerts: send a test transaction
- [ ] Emergency Signal group exists with all signers; not relying on Telegram/Discord
- [ ] Emergency proposal pre-staged in Squads; verify it's still executable
- [ ] Rollback tested on devnet within last 60 days

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **No fallback buffer** | Rollback impossible — must do full new deploy | Always keep `$PREVIOUS_BUFFER` live (rules R007) |
| **Slow signer coordination** | 45-minute response when 15 is needed | Pre-agree emergency channel, run quarterly drills |
| **Monitoring only successes** | Missing failed exploit attempts before success | Set Helius webhook `txnStatus: "all"` — capture failures too |
| **No pre-staged emergency proposal** | Creating a Squads proposal takes 10 minutes under stress | Pre-create the pause/rollback proposal, just don't execute it |
| **Relying on Discord/Telegram** | Communication platform may be inaccessible during an incident | Use Signal for incident response |

---

## Cross-links
- Program upgrade for rollback: [`upgrade-lifecycle.md`](./upgrade-lifecycle.md)
- Governance-based emergency: [`governance-action.md`](./governance-action.md)
- Monitoring via Helius: benchmark tx monitoring patterns in [`benchmarks/upgrade-lifecycle.md`](../benchmarks/upgrade-lifecycle.md)
