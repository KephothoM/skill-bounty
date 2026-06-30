# Cross-Chain Intents Skill

**Version**: 1.2 (June 2026)  
**Scope**: Intent-based cross-chain execution using Mayan, deBridge, Wormhole, Circle CCTP, and Hyperlane from Solana.

---

## Intent-Based vs. Direct Bridge — Why It Matters

Direct bridges (Wormhole legacy, Allbridge) require you to lock tokens on chain A and mint on chain B with a trusted relayer. If the bridge is exploited, your tokens can be drained at the bridge contract level ($320M Wormhole, Feb 2022).

Intent protocols (Mayan, deBridge Express) work differently: you express *what you want* (receive 1 ETH on Ethereum), solvers compete to fill it, and you only pay if it's done correctly. If no solver fills your order, it expires and your funds are returned.

**Use intent-based protocols for any cross-chain operation. Never use direct bridges on mainnet for production flows.**

---

## Supported Protocols (2026)

| Protocol | Model | Best For | Solana Support |
|---|---|---|---|
| **Mayan** | Intent / solver | SOL↔ETH/ARB/BSC, speed | ✅ Native |
| **deBridge Express** | Intent | Multi-chain, large amounts | ✅ Native |
| **Circle CCTP** | Direct (USDC only) | USDC moves (audited, minimal) | ✅ Native |
| **Wormhole NTT** | Native token transfers | Custom tokens, full control | ✅ Native |
| **Hyperlane** | Modular messaging | Custom security model | ✅ via ISM |

---

## Workflow: Mayan Intent (Solana → EVM)

### Step 1 — Get Quote

```typescript
import { fetchQuote, swapFromSolana } from "@mayanfinance/swap-sdk";
import { Connection, PublicKey } from "@solana/web3.js";

const quote = await fetchQuote({
  amountIn: 1_000_000_000,  // 1 SOL in lamports
  fromToken: "SOL",
  toToken: "ETH",
  fromChain: "solana",
  toChain: "ethereum",
  slippageBps: 50,           // 0.5% slippage tolerance
  referrerBps: 0,
});

console.log("Quote:", {
  expectedOutput: quote.expectedAmountOut,   // ETH amount
  minOutput:      quote.minAmountOut,        // worst-case with slippage
  solverFee:      quote.feeAmount,
  estimatedTime:  `${quote.eta}s`,
  route:          quote.route,
});
```

### Step 2 — Check Price Oracle Before Submitting

```typescript
// Always verify the quote against an independent oracle
// Mayan quotes can be stale if the solver is slow to update
import { PythHttpClient, getPythClusterApiUrl } from "@pythnetwork/client";

const pythClient = new PythHttpClient(connection, new PublicKey(PYTH_PROGRAM_ID));
const pythData = await pythClient.getData();
const solPrice = pythData.productPrice.get("Crypto.SOL/USD");

const impliedRate = quote.expectedAmountOut / (1.0); // ETH received per SOL
const oracleRate  = (solPrice?.price ?? 0) / ethPrice;

const deviation = Math.abs(impliedRate - oracleRate) / oracleRate;
if (deviation > 0.02) {  // > 2% deviation from oracle
  throw new Error(
    `Quote deviates ${(deviation * 100).toFixed(2)}% from oracle price. ` +
    `Possible solver manipulation or stale quote. Aborting.`
  );
}
```

### Step 3 — Execute Intent

```typescript
const txId = await swapFromSolana(
  quote,
  signerPublicKey,
  destinationAddress,  // EVM address to receive ETH
  null,                // referrer (optional)
  provider,
  connection,
  {
    skipPreflight: false,
    maxRetries: 3,
  }
);

console.log(`Intent submitted: ${txId}`);
console.log(`Track at: https://explorer.mayan.finance/tx/${txId}`);
```

### Step 4 — Monitor Completion

```typescript
// Poll for solver fulfillment (typically 15–60 seconds)
import { waitForFulfillment } from "@mayanfinance/swap-sdk";

const result = await waitForFulfillment(txId, {
  timeout: 120_000,   // 2 minute timeout
  onUpdate: (status) => console.log(`Status: ${status.state}`),
});

if (result.state !== "fulfilled") {
  console.error("Intent not fulfilled. Refund initiated automatically.");
  // Mayan auto-refunds on timeout — no action needed
}
```

---

## Workflow: Circle CCTP (USDC Only)

CCTP is a direct burn/mint protocol for USDC — the one exception to the "use intents" rule because:
1. It's audited by Circle directly
2. It's USDC-only (no arbitrary token risk)
3. It's 60%+ cheaper than intent protocols for pure USDC moves

```typescript
import { MessageTransmitter, TokenMessenger } from "@circle-fin/cross-chain-transfer-protocol";

// Burn USDC on Solana
const burnTx = await TokenMessenger.depositForBurn({
  amount: 100_000_000,           // 100 USDC (6 decimals)
  destinationDomain: 0,          // 0 = Ethereum, 3 = Arbitrum, 6 = Base
  mintRecipient: ethereumAddress,
  burnToken: USDC_MINT,
  connection,
  payer: signerKeypair,
});

// Wait for Circle attestation (~20 seconds)
const attestation = await Circle.getAttestation(burnTx.messageHash);

// Mint on destination (call from EVM side)
// MessageTransmitter.receiveMessage(messageBytes, attestation)
```

---

## Slippage and Route Scoring

For any cross-chain swap > $1,000:

```typescript
interface RouteScore {
  protocol: string;
  expectedOutput: number;
  minOutput: number;      // worst case
  solverFee: number;
  bridgeRisk: "low" | "medium" | "high";
  eta: number;            // seconds
  score: number;
}

function scoreRoute(quote: MayanQuote): RouteScore {
  const slippageImpact = 1 - quote.minAmountOut / quote.expectedAmountOut;
  const feeImpact = quote.feeAmount / quote.amountIn;

  // Score: higher is better
  // Penalize: slippage > 1%, fee > 0.5%, bridge risk
  const score = 100
    - (slippageImpact * 200)   // 1% slippage → -20 points
    - (feeImpact * 100)        // 0.5% fee → -50 points
    - (quote.route.includes("bridge") ? 10 : 0);  // direct bridge penalty

  return { ...quote, slippageImpact, score };
}
```

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **Direct bridge for large amounts** | Protocol exploit risk | Use intent protocols — Mayan or deBridge Express |
| **No oracle price check** | Accepting manipulated solver quote | Always compare to Pyth/Switchboard before executing |
| **No timeout handling** | UI hangs if solver doesn't fill | Use `waitForFulfillment` with 120s timeout; Mayan auto-refunds |
| **CCTP for non-USDC** | CCTP only supports USDC | Use NTT (Wormhole) or Mayan for custom tokens |
| **Slippage too tight on volatile assets** | Order never fills | Use ≥ 0.5% slippage for majors, ≥ 1.5% for alt tokens |

---

## Cross-links
- For verifiable cross-chain data: [`ai-agent-oracle.md`](./ai-agent-oracle.md)
- For x402 agent-to-agent payments (Solana-native): [`web3-privacy-payments.md`](./web3-privacy-payments.md)
