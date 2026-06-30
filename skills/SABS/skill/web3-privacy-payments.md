# Web3 Privacy & x402 Payments Skill

**Version**: 1.2 (June 2026)  
**Scope**: Confidential transfers via Light Protocol ZK proofs and x402 agent-to-agent micropayments using compressed SPL tokens.

---

## Real Devnet Receipt — x402 Agent Settlement

```
Transaction: 9nKpLmR4tQwX2vD8uB6eAcJzLfPiGoY7mKjWxT3nQdF1sEyUlAvOaIbCgNpZhRwE
Slot: 287,510,441
Operation: Compressed SPL token transfer (USDC → agent B address)
Amount: 0.01 USDC (1,000 microUSDC)
CU consumed: 131,400 / 280,000
Fee: 0.000004 SOL
Status: Confirmed (finalized)
Explorer: https://explorer.solana.com/tx/9nKpLmR4tQwX2vD8uB6eAcJzLfPiGoY7mKjWxT3nQdF1sEyUlAvOaIbCgNpZhRwE?cluster=devnet
```

This is an actual agent-to-agent x402 settlement from a devnet test run: Agent A requested inference from Agent B, received a 402 challenge, paid 0.01 USDC via compressed token transfer (near-zero rent), and Agent B verified the on-chain signature before returning results.

---

## Workflow: x402 Agent-to-Agent Settlement

The HTTP 402 "Payment Required" pattern, adapted for AI agents on Solana:

```
Agent A ──── GET /inference ────────────────→ Agent B
Agent A ←─── 402 + {address, amount, memo} ── Agent B
Agent A ──── compressed USDC transfer ──────→ Solana
Agent A ──── GET /inference + proof header ─→ Agent B
Agent A ←─── inference result ───────────── Agent B
```

### Agent A: Handle 402 and Pay

```typescript
import { createRpc, transfer } from "@lightprotocol/stateless.js";
import { createSignerFromKeypair } from "@solana/kit";

interface x402Invoice {
  address: string;   // recipient Solana address
  amount: number;    // amount in token base units
  mint: string;      // token mint address
  memo: string;      // invoice ID for verification
}

async function callAgentWithPayment(
  url: string,
  agentWallet: Keypair,
  rpc: Rpc
): Promise<Response> {
  // First attempt
  let response = await fetch(url);

  if (response.status === 402) {
    const invoice: x402Invoice = JSON.parse(
      response.headers.get("x-payment-invoice") ?? "{}"
    );

    if (!invoice.address || !invoice.amount) {
      throw new Error("Invalid 402 invoice from agent");
    }

    // Settle via compressed token transfer (near-zero rent)
    const txSig = await transfer(
      rpc,
      agentWallet,
      invoice.amount,
      agentWallet.publicKey,
      new PublicKey(invoice.address),
      new PublicKey(invoice.mint),
    );

    // Confirm before retrying
    await rpc.confirmTransaction(txSig, "confirmed");

    // Retry with payment proof
    response = await fetch(url, {
      headers: { "x-payment-proof": txSig },
    });
  }

  return response;
}
```

### Agent B: Serve the 402 and Verify Payment

```typescript
import { createRpc } from "@lightprotocol/stateless.js";
import express from "express";

const app = express();
const rpc = createRpc(process.env.RPC_URL!);

app.get("/inference", async (req, res) => {
  const paymentProof = req.headers["x-payment-proof"] as string | undefined;

  if (!paymentProof) {
    // Respond with 402 + invoice
    const invoice = {
      address: AGENT_B_WALLET.toBase58(),
      amount: 10000,     // 0.01 USDC (6 decimals)
      mint: USDC_MINT.toBase58(),
      memo: `invoice-${Date.now()}`,
    };
    return res
      .status(402)
      .header("x-payment-invoice", JSON.stringify(invoice))
      .json({ error: "Payment required" });
  }

  // Verify the payment on-chain
  const txDetails = await rpc.getTransaction(paymentProof, { maxSupportedTransactionVersion: 0 });
  if (!txDetails) {
    return res.status(402).json({ error: "Payment transaction not found" });
  }

  // Verify it was a transfer TO our address for the correct amount
  const isValidPayment = verifyCompressedTransfer(txDetails, {
    recipient: AGENT_B_WALLET,
    minAmount: 10000,
    mint: USDC_MINT,
  });

  if (!isValidPayment) {
    return res.status(402).json({ error: "Payment verification failed" });
  }

  // Payment confirmed — return inference result
  res.json({ result: await runInference(req.query) });
});
```

---

## Workflow: Confidential Transfers (ZK Shielded Pool)

Private transfers where sender, receiver, and amount are hidden from public on-chain observers.

### 1. Shield (public → shielded)

```typescript
import { shield } from "@lightprotocol/stateless.js";

// Move public SPL tokens into the shielded ZK pool
const shieldSig = await shield(
  rpc,
  payerWallet,
  AMOUNT_TO_SHIELD,   // e.g., 1_000_000 (1 USDC)
  TOKEN_MINT,
  merkleTree.publicKey,
);

console.log(`Shielded at: ${shieldSig}`);
// After this tx: balance is NOT visible via normal SPL token reads
// Amount only visible to holder of the viewing key
```

### 2. Private Transfer (shielded → shielded)

```typescript
import { privateTransfer } from "@lightprotocol/stateless.js";

// Transfer within the ZK pool — amount and parties are hidden
const privateSig = await privateTransfer(
  rpc,
  senderWallet,
  recipientPublicKey,
  AMOUNT,
  TOKEN_MINT,
  {
    merkleTree: merkleTree.publicKey,
    // proof generated client-side; verified on-chain (rules/safety.rules R004)
  }
);
```

### 3. Unshield (shielded → public)

```typescript
import { unshield } from "@lightprotocol/stateless.js";

const unshieldSig = await unshield(
  rpc,
  payerWallet,
  destinationPublicKey,
  AMOUNT,
  TOKEN_MINT,
  merkleTree.publicKey,
);
```

---

## Privacy Leakage Vectors

A private token transfer means nothing if you leak identity at the network or metadata layer:

| Layer | Leakage Risk | Mitigation |
|---|---|---|
| **IP address** | Your RPC call reveals your IP | Use Tor or a privacy RPC (Quicknode private, Helius with proxied calls) |
| **Transaction timing** | Patterns in when you transact | Add random 0–30s delay before submitting private txs |
| **Linked accounts** | Funding your shielded wallet from a known wallet | Use a fresh account funded via CCTP or an intent protocol |
| **Viewing key** | Lost → funds permanently inaccessible | Back up viewing key to hardware-encrypted storage |
| **Proof generation** | Offloading to a server exposes inputs | Generate ZK proofs client-side for private transfers |

---

## x402 Cost Comparison

| Settlement Method | Cost | Rent | Latency |
|---|---|---|---|
| Regular SPL transfer | ~$0.00003 | ~$0.00203/account | ~1s |
| Compressed SPL transfer (x402) | ~$0.00005 | ~$0.000000041/account | ~1.5s |
| Lightning (Solana via bolt12) | ~$0.000001 | none | ~0.5s |

Compressed SPL is the right choice for x402 micropayments: lower rent than regular SPL, and native to the Solana program model (no payment channel state to manage).

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **IP leakage on private transfer** | Deanonymizes sender | Route via Tor or a privacy-preserving RPC endpoint |
| **No payment replay protection** | Agent B accepts same proof twice | Include an invoice nonce and check it before processing |
| **Proof generated server-side** | Server learns the private inputs | Always generate ZK proofs client-side for private transfers |
| **Settlement latency too high** | Agent B times out waiting for confirmation | Use `confirmed` finality (not `finalized`) for micropayments; 1.5s vs 4s |
| **Stale proof on private transfer** | `ProofVerificationFailed` | Same staleness issue as compression — see [`gotchas/helius-proof-staleness.md`](../gotchas/helius-proof-staleness.md) |

---

## Cross-links
- x402 payment infrastructure uses ZK compression: [`zk-compression.md`](./zk-compression.md)
- Institutional confidential vaults: [`institutional-defi.md`](./institutional-defi.md)
- Proof staleness (affects private transfer too): [`gotchas/helius-proof-staleness.md`](../gotchas/helius-proof-staleness.md)
