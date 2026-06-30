# Institutional DeFi Skill

**Version**: 1.2 (June 2026)  
**Scope**: Custody integration, policy-enforced vaults, compliance reporting, and audit-ready position tracking on Solana.

---

## Overview

Institutional DeFi on Solana in 2026 means operating at the intersection of:
- **Custodial policy engines** (Fireblocks, Turnkey) for approval workflows
- **On-chain position transparency** (Kamino, Marginfi, Drift) for NAV reporting
- **Regulatory hooks** (Travel Rule, MiCA-adjacent frameworks) for compliance data
- **ZK-based privacy** where confidentiality is required (see [`web3-privacy-payments.md`](./web3-privacy-payments.md))

---

## Key Integrations

### Fireblocks Policy Engine

Fireblocks wraps your Solana signing with policy-enforced approval chains. Key patterns:

```typescript
import { FireblocksSDK, PeerType, TransactionOperation } from "fireblocks-sdk";

const fireblocks = new FireblocksSDK(privateKey, apiKey);

// Create a Solana raw transaction through Fireblocks
const { id, status } = await fireblocks.createTransaction({
  operation: TransactionOperation.RAW,
  assetId: "SOL",
  source: { type: PeerType.VAULT_ACCOUNT, id: "0" },
  note: "SABS: Kamino position adjustment — requires 2/3 policy approval",
  extraParameters: {
    rawMessageData: {
      messages: [{
        content: serializedTxBase64,   // your Solana tx, base64 encoded
        derivationPath: [44, 501, 0, 0],
      }]
    }
  }
});

// Poll for approval (blocks until policy satisfied)
await waitForTxCompletion(fireblocks, id);
```

**Critical**: Fireblocks policy rules for DeFi operations should require:
- Amount threshold: auto-approve < $10k, 1/3 approval for $10k–$100k, 2/3 for > $100k
- Whitelist: only approved program IDs (Kamino `KAMNo...`, Marginfi `MFv2...`)
- Time lock: no executions between 23:00–06:00 UTC without emergency override

### Turnkey (alternative to Fireblocks)

```typescript
import { TurnkeyClient } from "@turnkey/sdk-server";
import { createActivityPoller } from "@turnkey/http";

const client = new TurnkeyClient({ baseUrl: "https://api.turnkey.com" }, stamper);

const signResult = await client.signTransaction({
  type: "ACTIVITY_TYPE_SIGN_TRANSACTION_V2",
  organizationId: process.env.TURNKEY_ORG_ID!,
  parameters: {
    signWith: process.env.TURNKEY_PRIVATE_KEY_ID!,
    unsignedTransaction: serializedTxHex,
    type: "TRANSACTION_TYPE_SOLANA",
  },
});
```

---

## Vault Architecture

### Segment Your Vaults — This Is Not Optional

Single-vault failure is a critical risk (see `rules/safety.rules` R006 for the upgrade case — same principle applies to DeFi capital).

Recommended segmentation:

```
┌─────────────────────────────────────────────────┐
│                 INSTITUTIONAL SETUP              │
├────────────────┬────────────────┬────────────────┤
│  COLD VAULT    │  HOT VAULT     │  UPGRADE VAULT │
│  (long-term)   │  (operations)  │  (authorities) │
│  4/7 Squads    │  2/5 Squads    │  3/5 Squads    │
│  72h time lock │  6h time lock  │  24h time lock │
│  Fireblocks    │  Turnkey       │  Hardware only │
├────────────────┴────────────────┴────────────────┤
│  Policy: never more than 20% in hot at one time  │
└─────────────────────────────────────────────────┘
```

---

## Daily NAV + Risk Reporting

### Position Fetching (Kamino + Marginfi)

```typescript
import { KaminoMarket } from "@kamino-finance/klend-sdk";
import { MarginfiClient } from "@mrgnlabs/marginfi-client-v2";

// Kamino positions
const kaminoMarket = await KaminoMarket.load(connection, KAMINO_MARKET_ADDRESS);
const obligations = await kaminoMarket.getAllObligationsForMarket();
const myObligation = obligations.find(o => o.obligationOwner.equals(vaultPubkey));

const nav = {
  depositedValue: myObligation?.refreshedStats.userTotalDeposit.toNumber() ?? 0,
  borrowedValue:  myObligation?.refreshedStats.userTotalBorrow.toNumber() ?? 0,
  netValue:       myObligation?.refreshedStats.netAccountValue.toNumber() ?? 0,
  healthFactor:   myObligation?.refreshedStats.leverage.toNumber() ?? 0,
};

// Marginfi positions
const mfiClient = await MarginfiClient.fetch(mfiConfig, wallet, connection);
const mfiAccount = await mfiClient.getMarginfiAccountByPubkey(vaultPubkey);
const mfiBalances = mfiAccount.balances.filter(b => b.active);
```

### Automated NAV Report (daily cron)

```typescript
// Run via Helius webhook trigger or external cron
async function generateDailyNAVReport(date: string) {
  const positions = await fetchAllPositions();
  const prices    = await fetchOraclePrices(); // Switchboard or Pyth

  const report = {
    date,
    totalAUM: positions.reduce((sum, p) => sum + p.usdValue, 0),
    positions: positions.map(p => ({
      protocol: p.protocol,
      asset: p.asset,
      amount: p.amount,
      usdValue: p.usdValue,
      apy: p.currentApy,
    })),
    riskMetrics: {
      maxDrawdown30d: calculateMaxDrawdown(positions, 30),
      weightedHealthFactor: calculateWeightedHealth(positions),
      liquidationDistance: calculateLiquidationBuffer(positions),
    },
    onChainProof: await generateHeliusDASProof(positions), // audit trail
  };

  // Export for compliance — use Helius DAS for on-chain proof
  await exportToComplianceSystem(report);
  return report;
}
```

---

## Travel Rule Compliance

The Travel Rule requires sharing sender/receiver identity data for transfers > $1,000 (varies by jurisdiction). On Solana, this requires hooking into your custody layer.

```typescript
import { TravelRuleClient } from "@notabene/javascript-sdk";

const travelRule = new TravelRuleClient({ apiKey: process.env.NOTABENE_API_KEY! });

// Before any large transfer, create a Travel Rule payload
async function createCompliantTransfer(
  fromVasp: string,
  toAddress: string,
  amount: number,
  asset: string
) {
  if (amount > 1000) {
    const trPayload = await travelRule.createTransfer({
      transactionAsset: asset,
      transactionAmount: amount.toString(),
      originatorVasp: { did: fromVasp },
      originatorEqualsBeneficiary: false,
      beneficiaryVasp: { did: await travelRule.getVaspDid(toAddress) },
      beneficiaryAccountNumber: toAddress,
    });

    // Attach payload to tx memo or off-chain compliance ledger
    await submitCompliancePayload(trPayload);
  }

  return buildSolanaTransfer(toAddress, amount, asset);
}
```

---

## Audit Trail with Helius DAS

```typescript
// Generate tamper-evident on-chain proof of position state
async function generateHeliusDASProof(positions: Position[]) {
  const response = await fetch(
    `https://api.helius.xyz/v0/addresses/${vaultAddress}/transactions?api-key=${HELIUS_API_KEY}&type=DeFi`
  );
  const txHistory = await response.json();

  return {
    merkleRoot: computeMerkleRoot(txHistory),
    latestSlot: txHistory[0]?.slot,
    positionCount: positions.length,
    // This root can be independently verified against on-chain data
  };
}
```

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **Single vault** | One compromise drains everything | Segment cold/hot/upgrade vaults — see architecture above |
| **Stale oracle prices in NAV** | Incorrect liquidation distance, bad risk reports | Always use < 60s old oracle data; Pyth and Switchboard have freshness checks |
| **No Travel Rule on large transfers** | Regulatory non-compliance | Hook into Notabene or similar VASP network; amount threshold varies by jurisdiction |
| **No liquidation monitoring** | Surprise liquidation, AUM loss | Set up Helius webhook on your vault address; alert if health factor < 1.2 |
| **Fireblocks policy too permissive** | Unauthorized transactions | Test policy by submitting just-over-threshold transactions manually before going live |

---

## Cross-links
- Confidential vault state transitions: [`web3-privacy-payments.md`](./web3-privacy-payments.md)
- Upgrade authority governance: [`upgrade-lifecycle.md`](./upgrade-lifecycle.md)
- Emergency vault pause: [`disaster-recovery.md`](./disaster-recovery.md)
