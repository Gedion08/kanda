# L6 Partner API and SDK

The Partner API is how ramps, integrators and market makers plug into Kanda: REST with signed requests, idempotent writes and signed webhooks, described in one OpenAPI 3.1 file that generates the SDK, the app client and the docs. A partner should be able to settle a sandbox payment in one day of integration work.

## 1. Conventions

- Base URLs: https://api.kanda.example/v1 (prod) and https://sandbox.kanda.example/v1; the domain is a placeholder.
- Source of truth: api/openapi.yaml in the monorepo; CI fails if the server's routes and the spec drift.
- JSON only; amounts are decimal strings in major units with the currency code beside them; KND amounts are decimal strings with up to 18 decimals.
- Timestamps ISO 8601 UTC. Ids are prefixed: qt\_, pay\_, ptn\_, bnf\_, evt\_.
- Cursor pagination with limit up to 100.
- Errors are RFC 9457 problem+json with a stable code.

## 2. Authentication

| Header | Value |
| --- | --- |
| X-Kanda-Key | API key id |
| X-Kanda-Timestamp | Unix seconds; rejected if more than 300 s from server time |
| X-Kanda-Signature | hex(HMAC-SHA256(secret, timestamp + newline + METHOD + newline + path with query + newline + sha256hex(body))) |
| Idempotency-Key | Required on every POST; UUID recommended |

Secrets rotate with overlap: two active secrets per key for 7 days. Optional mTLS and IP allowlists per partner.

## 3. Endpoints

| Method | Path | Caller | Purpose | Phase |
| --- | --- | --- | --- | --- |
| GET | /corridors | Any | Open corridors, limits, fees | P1 |
| GET | /nav | Any | NAV, health, basket | P1 |
| GET | /reserves | Any | Supply and coverage per leg | P1 |
| POST | /quotes | Business, integrator | Create all-in quote | P1 |
| GET | /quotes/{id} | Business, integrator | Read quote | P1 |
| POST | /payments | Business, integrator | Create payment from a locked quote | P1 |
| GET | /payments/{id} | Business, integrator, partner | Read payment with timeline | P1 |
| GET | /payments | Business, integrator | List with filters | P1 |
| POST | /payments/{id}/cancel | Business | Cancel before funding | P1 |
| GET | /partner/inbox | Partner | Payments needing action | P1 |
| POST | /partner/payments/{id}/funding-confirmations | Sending partner | Fiat received from customer | P1 |
| GET | /partner/payments/{id}/lock-transaction | Sending partner | Unsigned lock calldata | P1 |
| POST | /partner/payments/{id}/lock-submissions | Sending partner | Report lock transaction hash | P1 |
| POST | /partner/payments/{id}/payout-confirmations | Receiving partner | Fiat paid to beneficiary | P1 |
| POST | /partner/payments/{id}/rejections | Receiving partner | Refuse before payout | P1 |
| GET | /partner/statements/{date} | Partner | Kanda's view of the day | P1 |
| POST | /partner/statements | Partner | Partner's statement for reconciliation | P1 |
| POST, GET, DELETE | /webhooks | Partner, integrator | Manage endpoints | P1 |
| POST | /beneficiaries | Business | Add beneficiary | P1 |
| POST | /rfq/requests | Partner, integrator | Ask market makers for a price | P2 |
| POST | /rfq/quotes | Market maker | Submit signed EIP-712 quote | P2 |
| GET | /rfq/requests/{id} | Requester | Best quote and settlement calldata | P2 |

Partners also implement one endpoint Kanda calls: GET /kanda/v1/quote, specified in L2 section 4.

## 4. Examples

Create a quote:

```http
POST /v1/quotes
Idempotency-Key: 6f1c...
{
  "corridor": "KE-NG",
  "amount": { "value": "1290000.00", "currency": "KES", "side": "send" },
  "businessId": "bus_..."
}
```

Response: the quote object in L2 section 4.

Create a payment:

```http
POST /v1/payments
Idempotency-Key: 91ab...
{
  "quoteId": "qt_...",
  "beneficiaryId": "bnf_...",
  "invoice": { "number": "INV-2291", "fileId": "file_..." },
  "purpose": "goods_import"
}
```

Lock transaction for the sending partner:

```json
{
  "chainId": 8453,
  "to": "0xPaymentEscrow...",
  "data": "0x...",
  "value": "0",
  "approval": { "token": "0xKND...", "spender": "0xPaymentEscrow...", "amount": "9812450000000000000000", "permitAvailable": true },
  "summary": { "intentId": "0x...", "amountKnd": "9812.45", "receiverPartner": "ptn_ng_...", "expiry": "2026-10-01T14:10:00Z" }
}
```

Webhook envelope:

```json
{
  "id": "evt_...",
  "type": "intent.locked",
  "sequence": 5,
  "createdAt": "2026-10-01T10:12:03Z",
  "data": { "paymentId": "pay_...", "status": "LOCKED", "txHash": "0x..." }
}
```

Webhook headers: X-Kanda-Event-Id, X-Kanda-Timestamp, X-Kanda-Signature computed like request signatures over the raw body.

## 5. RFQ (P2)

1. Requester posts pair, side, amount and deadline.
2. Kanda fans out to registered market makers; each returns an EIP-712 quote signed for RFQSettler (L1 section 3.8) within 1 s.
3. Kanda returns the best quote and settlement calldata; requester submits on-chain before expiry.
4. Fills are indexed and reported to both sides; unfilled quotes expire harmlessly.

## 6. ISO 20022 mapping (P3)

| Kanda field | pacs.008 element |
| --- | --- |
| payment id | EndToEndId; UETR generated per payment |
| originator business | Dbtr, DbtrAcct |
| sending partner | DbtrAgt |
| beneficiary | Cdtr, CdtrAcct |
| receiving partner | CdtrAgt |
| receive amount and currency | IntrBkSttlmAmt, InstdAmt |
| rates | XchgRate |
| fees | ChrgsInf |
| invoice reference | RmtInf |

Status maps to pacs.002: LOCKED as accepted in process, COMPLETED as accepted settlement completed, CANCELLED and REFUNDED as rejected with a reason code.

## 7. Error codes (starting set)

| Code | HTTP | Meaning |
| --- | --- | --- |
| quote\_expired | 409 | Quote lock passed |
| quote\_held | 409 | Quote awaiting ops approval |
| corridor\_closed | 409 | Corridor paused or closed |
| limit\_exceeded | 422 | Business, corridor or partner limit |
| compliance\_hold | 409 | Payment held by compliance |
| invalid\_state | 409 | Action not allowed in current state |
| signature\_invalid | 401 | HMAC or EIP-712 signature failed |
| idempotency\_conflict | 409 | Same key, different body |
| partner\_timeout | 504 | Partner quote endpoint did not answer |

## 8. TypeScript SDK

Package @kanda/sdk, generated types from openapi.yaml plus hand-written helpers.

```ts
import { KandaClient, verifyWebhook } from '@kanda/sdk';
import { createWalletClient, http } from 'viem';
import { base } from 'viem/chains';

const kanda = new KandaClient({ keyId, secret, env: 'sandbox' });

const inbox = await kanda.partner.inbox();
for (const p of inbox.toLock) {
  const tx = await kanda.partner.getLockTransaction(p.id);
  const hash = await kanda.partner.signAndSubmitLock(tx, walletClient); // approve or permit, then lock
  await kanda.partner.reportLock(p.id, hash);
}

// in your webhook handler
const event = verifyWebhook(rawBody, headers, webhookSecret);
```

Helpers: request signing, retries with idempotency keys, webhook verification, lock and approval building with viem, amount parsing without floats.

## 9. Sandbox

- Mock partners for every corridor and a Base Sepolia deployment with a test KND faucet for partners.
- Magic amounts drive scenarios: an amount ending in .13 triggers a screening hit; .44 makes the receiving partner time out; .66 causes a dispute; .99 makes the partner quote diverge beyond threshold.
- A simulator endpoint advances time for an intent in sandbox only.

## 10. Versioning

Additive changes ship without a version bump; breaking changes create /v2 with at least 6 months overlap; deprecations announced by email and a Sunset header.

## 11. Partner technical onboarding checklist

- [ ] Sandbox keys issued, first signed request succeeds
- [ ] Quote endpoint implemented and signing verified
- [ ] Webhook endpoint verified and deduplicating
- [ ] Happy path, expiry refund and rejection scenarios passed in sandbox
- [ ] Daily statement upload matches Kanda's for 5 sandbox days
- [ ] Production wallet registered with signed ownership proof; lock tested with a small amount

## 12. Agent tasks

1. Write api/openapi.yaml covering section 3 with schemas from L2 and L3.
2. Add a CI check that compares Hono routes against the spec.
3. Generate packages/sdk types and implement the helpers in section 8 with tests against the sandbox.
4. Build the sandbox mock partners and magic-amount scenarios.
5. Publish docs from the spec with examples.
