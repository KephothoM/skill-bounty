# AI Agent Oracle Skill

**Version**: 1.2 (June 2026)  
**Scope**: Verifiable on-chain inference results using Ritual/Giza, Switchboard custom feeds, and SP1/Succinct zkVM proofs.

---

## Overview

AI oracle on Solana means getting an off-chain computation (an LLM inference, an ML model prediction, a risk score) onto the chain with a *verifiable proof* that the computation was done correctly. There are two main approaches:

| Approach | Latency | CU to Verify | Trust Model | Use Case |
|---|---|---|---|---|
| **Switchboard custom feed** | ~2s | ~10k CU | Economic (staking) | Price feeds, aggregated off-chain data |
| **SP1 (Succinct) zkVM** | ~30–120s | ~214k CU | Cryptographic (ZK) | ML predictions, risk scores, sensitive decisions |
| **Ritual / Giza** | ~60–180s | ~150k CU | Cryptographic (ZK) | LLM inference, model output attestation |

---

## Approach 1: Switchboard Custom Oracle Feed

Switchboard lets you define a custom off-chain aggregator job and publish results on-chain with economic security (operators stake SWITCH that's slashable for misbehavior).

### Step 1 — Define Your Job (YAML)

```yaml
# switchboard-job.yaml
# Runs an inference API call and aggregates results from 3 oracles
tasks:
  - httpTask:
      url: "https://your-inference-api.com/predict"
      method: POST
      headers:
        - key: "Content-Type"
          value: "application/json"
      body: '{"input": "${INPUT_PARAM}"}'
  - jsonParseTask:
      path: "$.result.score"
  - multiplyTask:
      scalar: 1000000  # scale to integer (6 decimals)
```

### Step 2 — Create Feed On-chain

```typescript
import { SwitchboardProgram, AggregatorAccount, OracleJob } from "@switchboard-xyz/solana.js";
import * as sb from "@switchboard-xyz/common";

const switchboard = await SwitchboardProgram.fromProvider(provider);

const [aggregatorAccount, aggregatorInit] = await AggregatorAccount.create(
  switchboard,
  {
    name: Buffer.from("AI Risk Score"),
    batchSize: 3,               // 3 oracles must agree
    minRequiredOracleResults: 2,
    minRequiredJobResults: 2,
    minUpdateDelaySeconds: 30,
    oracleRequestBatchSize: 3,
    fundAmount: 0.5,            // SOL to fund update costs
    authority: authority.publicKey,
    jobs: [
      { weight: 2, data: OracleJob.encodeDelimited(inferenceJob).finish() },
    ],
  }
);
await aggregatorInit.send();

// Read result on-chain
const result = await aggregatorAccount.fetchLatestValue();
console.log("Latest oracle value:", result?.toNumber() / 1e6);
```

### Step 3 — Consume in Your Program (Rust/Anchor)

```rust
use switchboard_solana::AggregatorAccountData;

#[derive(Accounts)]
pub struct UseOracle<'info> {
    pub aggregator: AccountLoader<'info, AggregatorAccountData>,
}

pub fn use_oracle(ctx: Context<UseOracle>) -> Result<()> {
    let feed = &ctx.accounts.aggregator.load()?;

    // Check freshness — stale data is as bad as wrong data
    let current_slot = Clock::get()?.slot;
    let last_updated_slot = feed.latest_confirmed_round.round_open_slot;
    require!(
        current_slot - last_updated_slot < 150, // ~60 second freshness window
        OracleError::StaleFeed
    );

    let value = feed.get_result()?;
    msg!("Oracle value: {}", value.mantissa);
    Ok(())
}
```

---

## Approach 2: SP1 (Succinct) zkVM Proof

SP1 lets you write your oracle computation in Rust, prove it with a zkVM, and verify the proof on Solana with ~214k CU.

### Step 1 — Write Your Program (Rust)

```rust
// sp1-oracle/program/src/main.rs
#![no_main]
sp1_zkvm::entrypoint!(main);

use sp1_zkvm::io;

pub fn main() {
    // Read private inputs (your ML model weights, input data)
    let model_weights: Vec<f32> = io::read_vec();
    let input_features: Vec<f32> = io::read_vec();

    // Run inference (simple linear model example)
    let prediction: f32 = model_weights.iter()
        .zip(input_features.iter())
        .map(|(w, x)| w * x)
        .sum();

    // Scale and publish as public output
    let scaled = (prediction * 1_000_000.0) as i64;
    io::commit(&scaled);
}
```

### Step 2 — Generate Proof Off-chain

```typescript
import { ProverClient } from "@succinct/sp1-sdk";

const client = new ProverClient({ rpcUrl: "https://rpc.succinct.xyz" });

const proof = await client.prove({
  programPath: "./sp1-oracle/elf/program",
  stdin: {
    modelWeights: loadWeights("./model.bin"),
    inputFeatures: currentInputData,
  },
  proofType: "groth16",  // Groth16 is verifiable on Solana; STARK would be too large
});

console.log("Proof generated:", proof.bytes.slice(0, 16), "...");
// Submit proof + public values to your Solana program
```

### Step 3 — Verify On-chain (Rust/Anchor)

```rust
use sp1_solana::SP1Verifier;

#[derive(Accounts)]
pub struct VerifyAndStore<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(mut)]
    pub oracle_state: Account<'info, OracleState>,
    /// CHECK: verified by SP1Verifier
    pub sp1_verifier: UncheckedAccount<'info>,
}

pub fn verify_and_store(
    ctx: Context<VerifyAndStore>,
    proof: Vec<u8>,
    public_values: Vec<u8>,
    vk_hash: [u8; 32],
) -> Result<()> {
    // Cryptographic verification on-chain — never trust off-chain (rules/safety.rules R004)
    SP1Verifier::verify_groth16(&proof, &vk_hash, &public_values)
        .map_err(|_| OracleError::ProofVerificationFailed)?;

    // Decode public outputs
    let prediction = i64::from_le_bytes(public_values[..8].try_into().unwrap());

    // Store with timestamp for freshness checking
    let oracle = &mut ctx.accounts.oracle_state;
    oracle.value = prediction;
    oracle.last_updated_slot = Clock::get()?.slot;
    oracle.vk_hash = vk_hash;

    msg!("Verified oracle prediction: {}", prediction);
    Ok(())
}
```

---

## Freshness Windows — Critical

| Oracle Type | Max Acceptable Staleness | How to Enforce |
|---|---|---|
| Price data | 30 seconds | `current_slot - last_slot < 75` (400ms/slot) |
| Risk scores | 60 seconds | `current_slot - last_slot < 150` |
| ML predictions | 5 minutes | `current_slot - last_slot < 750` |
| Governance data | 1 block | Always fetch fresh before governance action |

**Never** use an oracle result without a freshness check. A stale price feed was the root cause of the Mango Markets exploit.

---

## Cost Comparison (Devnet Measured)

| Operation | CU Cost | Latency | Notes |
|---|---|---|---|
| Switchboard read (on-chain) | ~10,000 CU | instant | Just a program call |
| SP1 Groth16 verify | ~214,000 CU | ~120s off-chain | Proof gen is the bottleneck |
| Ritual verify (EVM→Solana) | ~150,000 CU | ~180s | Cross-chain relay adds latency |

**Optimization**: Offload proof generation to a dedicated proving service or Succinct's hosted prover. Never generate Groth16 proofs on the user's machine for production — latency is 2–5 minutes.

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **No freshness check** | Stale data treated as current | Always check slot age; see freshness table above |
| **STARK proof on Solana** | Transaction too large (10KB limit) | Convert to Groth16 using Succinct's `stark-to-groth16` pipeline |
| **Trusting off-chain proof** | Unverified result accepted | Verify proof on-chain via `SP1Verifier::verify_groth16` — non-negotiable (rules R004) |
| **Proving key mismatch** | Verification always fails | Commit your proving key hash (`vk_hash`) on-chain and check it on verify |
| **Heavy compute in same tx** | CU budget exceeded | Proof verify tx should be isolated — don't bundle it with business logic |

---

## Cross-links
- Using oracle results for privacy payments: [`web3-privacy-payments.md`](./web3-privacy-payments.md)
- Cross-chain oracle data via Wormhole: [`cross-chain-intents.md`](./cross-chain-intents.md)
- CU budget planning: [`gotchas/cu-budget-overruns.md`](../gotchas/cu-budget-overruns.md)
