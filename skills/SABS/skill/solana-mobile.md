# Solana Mobile Development

**Version**: 1.2 (June 2026)  
**Scope**: Mobile Wallet Adapter v2, Secure Enclave signing, Expo/React Native, and background transaction flows on Saga/SMS.

---

## Core Stack (2026)

| Layer | Technology | Notes |
|---|---|---|
| **Signing** | MWA v2 (`@solana-mobile/mobile-wallet-adapter-protocol-web3js`) | Stateless; auth tokens expire |
| **Hardware security** | Secure Enclave (Saga) / StrongBox (Android) | Biometric-gated key storage |
| **Framework** | Expo + React Native | Works on Saga and standard Android |
| **Background tx** | Firebase FCM + Helius webhooks | Push-to-sign flow |

---

## Connecting to MWA v2

```typescript
import {
  transact,
  Web3MobileWallet,
} from "@solana-mobile/mobile-wallet-adapter-protocol-web3js";
import { Connection, PublicKey, Transaction } from "@solana/web3.js";

async function signAndSendWithMWA(
  connection: Connection,
  transaction: Transaction
): Promise<string> {
  return await transact(async (wallet: Web3MobileWallet) => {
    // Step 1: Authorize (first time only; subsequent calls use cached auth token)
    const { accounts, auth_token } = await wallet.authorize({
      cluster: "devnet",
      identity: {
        name: "SABS Demo App",
        uri: "https://github.com/kephothoM/SABS",
        icon: "/favicon.ico",
      },
    });

    const userPublicKey = new PublicKey(accounts[0].address);

    // Step 2: Sign transaction
    const { blockhash } = await connection.getLatestBlockhash();
    transaction.recentBlockhash = blockhash;
    transaction.feePayer = userPublicKey;

    const signedTxs = await wallet.signTransactions({
      transactions: [transaction],
    });

    // Step 3: Send
    const sig = await connection.sendRawTransaction(signedTxs[0].serialize());
    return sig;
  });
}
```

---

## Secure Enclave Key Generation (Saga)

**Never store raw private keys in AsyncStorage, SecureStore, or app state.**  
Always use the Secure Enclave via MWA — the key never leaves the hardware element.

```typescript
// ❌ WRONG — never do this
import * as SecureStore from "expo-secure-store";
const privateKey = await SecureStore.getItemAsync("wallet_key");
// If the device is compromised, the key is compromised.

// ✅ CORRECT — key generation happens inside the wallet app, on the Secure Enclave
// Your app never sees the private key bytes. It only sees:
// 1. The public key (from accounts[0].address in wallet.authorize())
// 2. A signature (from wallet.signTransactions())
// The wallet app handles all biometric prompts and key storage.
```

For situations where you need app-side key management (e.g., background signing without user interaction), use the **Turnkey SDK** which is backed by hardware-attested TEEs:

```typescript
import { TurnkeyClient } from "@turnkey/sdk-server";
// Keys are stored in Turnkey's AWS Nitro Enclave — not in your app's storage
```

---

## Background Push → Sign Flow

Use case: a DeFi position needs to be closed immediately (approaching liquidation), even if the user isn't actively using the app.

```
Helius webhook → your server → Firebase FCM → Saga app → MWA sign → Solana
```

### Server Side (sends the push)

```typescript
import admin from "firebase-admin";

// When Helius detects your monitored condition (e.g., health factor < 1.1)
async function sendUrgentSignRequest(
  fcmToken: string,
  transaction: string,    // base64 serialized transaction
  urgency: "high" | "normal"
) {
  await admin.messaging().send({
    token: fcmToken,
    android: {
      priority: urgency === "high" ? "high" : "normal",
      notification: {
        title: "⚠️ Action Required",
        body: "Your position is near liquidation. Tap to review and sign.",
        channelId: "urgent_transactions",
      },
    },
    data: {
      type: "SIGN_REQUEST",
      transaction,    // app deserializes and presents for signing
      deadline: String(Date.now() + 5 * 60 * 1000),  // 5 min to act
    },
  });
}
```

### App Side (handles the push)

```typescript
import messaging from "@react-native-firebase/messaging";
import { transact } from "@solana-mobile/mobile-wallet-adapter-protocol-web3js";

// Register background message handler
messaging().setBackgroundMessageHandler(async (remoteMessage) => {
  if (remoteMessage.data?.type === "SIGN_REQUEST") {
    // Show a notification — tap opens the signing UI
    // DO NOT auto-sign without user interaction (security)
    await showSigningNotification(remoteMessage.data);
  }
});

// In the signing UI component
async function handleSigningRequest(txBase64: string) {
  const tx = Transaction.from(Buffer.from(txBase64, "base64"));

  return await transact(async (wallet) => {
    const [signedTx] = await wallet.signTransactions({ transactions: [tx] });
    const sig = await connection.sendRawTransaction(signedTx.serialize());
    return sig;
  });
}
```

---

## Offline Resilience: Queue + Retry

Mobile connections drop. Never assume a transaction that was submitted was confirmed.

```typescript
import AsyncStorage from "@react-native-async-storage/async-storage";

interface PendingTx {
  id: string;
  serialized: string;     // base64 serialized signed tx
  submittedAt: number;
  maxRetries: number;
  retryCount: number;
}

// After signing, queue the tx before sending
async function queueAndSend(signedTx: Transaction): Promise<string> {
  const pending: PendingTx = {
    id: `tx_${Date.now()}`,
    serialized: Buffer.from(signedTx.serialize()).toString("base64"),
    submittedAt: Date.now(),
    maxRetries: 5,
    retryCount: 0,
  };

  // Persist before sending — if we crash mid-send, we can retry
  const queue = JSON.parse(await AsyncStorage.getItem("tx_queue") ?? "[]");
  queue.push(pending);
  await AsyncStorage.setItem("tx_queue", JSON.stringify(queue));

  return await sendWithRetry(pending);
}

async function sendWithRetry(pending: PendingTx): Promise<string> {
  for (let i = 0; i <= pending.maxRetries; i++) {
    try {
      const tx = Transaction.from(Buffer.from(pending.serialized, "base64"));
      const sig = await connection.sendRawTransaction(tx.serialize(), {
        skipPreflight: false,
        maxRetries: 0,  // we handle retries ourselves
      });
      await connection.confirmTransaction(sig, "confirmed");
      // Remove from queue on success
      await removePendingTx(pending.id);
      return sig;
    } catch (err) {
      if (i === pending.maxRetries) throw err;
      await sleep(Math.min(1000 * 2 ** i, 30_000)); // exponential backoff, max 30s
    }
  }
  throw new Error("Max retries exceeded");
}
```

---

## Common Pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| **Raw key in SecureStore** | Key exposed if device is jailbroken | Use MWA (key never leaves wallet app's Secure Enclave) |
| **Auth token not refreshed** | `AuthorizationNotValid` error on second tx | Re-authorize if auth token age > 30 min; store token expiry |
| **Auto-signing on push** | Silent malicious tx if push is spoofed | Always require user biometric confirmation before signing |
| **No retry on network drop** | User thinks tx submitted; it wasn't | Queue signed tx before sending; retry with backoff |
| **Deep link signing on wrong cluster** | Devnet tx signed against mainnet state | Always check cluster in `wallet.authorize()` response |

---

## Cross-links
- Signing upgrade proposals from mobile: [`upgrade-lifecycle.md`](./upgrade-lifecycle.md)
- x402 micropayments from mobile agents: [`web3-privacy-payments.md`](./web3-privacy-payments.md)
