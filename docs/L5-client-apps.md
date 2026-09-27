# L5 Client apps

Kanda has five front ends: a business app, a partner portal, an admin console, a public transparency page, and from P2 a mobile app. All share one React stack and one UI package; every screen shows money in the user's local currency first and KND second.

## 1. Apps

| App | Users | Phase | Auth | Core screens |
| --- | --- | --- | --- | --- |
| Business app | SME makers, approvers, viewers | P1 | OIDC plus WebAuthn step-up; optional wallet connect | Dashboard, new payment, payments, beneficiaries, team, holdings |
| Partner portal | Ramp partner operators | P1 | OIDC with SSO, hardware-key MFA; partner wallet via RainbowKit or Safe | Inbox, lock, confirm payout, inventory, statements, API keys |
| Admin console | Kanda ops, compliance, treasury | P1 | SSO with hardware keys, role-based | Corridors, partners, participants, intents, cases, recon, proposals, audit log |
| Transparency page | Public | P0 prototype, P1 | None | Supply, reserves, coverage, NAV, contracts, roles, timelock queue |
| Mobile app | Businesses and individuals | P2 | Passkey smart account | Balance, send, receive, cash out, history |

## 2. Shared stack and layout

- React, Vite, TypeScript strict, TanStack Router and Query, react-hook-form with zod, Tailwind with shadcn/ui, wagmi 2 and viem, RainbowKit where a wallet is needed, i18next (English first, Swahili and French next).
- Money display through one helper: formatMoney(amount, currency, locale) using Intl.NumberFormat; KND shown with 2 decimals in UI, full precision in tooltips.
- Generated API client from the OpenAPI spec (L6); no hand-written fetch calls.
- Performance budget: under 250 KB gzipped initial JavaScript per app; usable on 3G; skeleton states everywhere.

```
apps/
  business/  partner/  admin/  transparency/  mobile/ (P2)
packages/
  ui/        shadcn components, theme, MoneyText, StatusTimeline, TxLink, CountdownBadge
  api-client/ generated from openapi.yaml
  chain/     ABIs, addresses, wagmi config
```

## 3. Business app

| Screen | Contents | Rules |
| --- | --- | --- |
| Dashboard | Payments in progress with state, last 30 days volume, holdings value in local currency | State labels match L3 orchestrator states |
| New payment | Step 1 beneficiary; step 2 amount in send or receive currency, invoice upload; step 3 quote with 10-minute countdown and full fee breakdown; step 4 approval | Quote refresh when expired; approval uses WebAuthn step-up; makers cannot approve their own payment when policy requires two people |
| Payment detail | Status timeline, amounts, rates, rate basis, fees, on-chain transaction links, payout reference, downloadable receipt | Timeline driven by intent\_events |
| Beneficiaries | Saved suppliers with bank details, country, verification state | Adding one needs step-up |
| Team | Users, roles, approval policy (amount thresholds, two-person rule) | Admin only |
| Holdings | KND balance for connected self-custody wallets; value in KES, NGN and USD; NAV and health badge; redeem through partner | Clear disclosure that KND's USD value moves with gold |

## 4. Partner portal

| Screen | Contents | Rules |
| --- | --- | --- |
| Inbox | Intents awaiting funding confirmation, lock, payout confirmation; SLA timers | Sorted by nearest deadline |
| Lock | Intent summary, Travel Rule status, Build transaction, sign with connected wallet or propose to partner's Safe | Disabled until Travel Rule accepted |
| Confirm payout | Payout reference, bank or mobile money channel, timestamp | Required fields validated per country |
| Inventory | Wallet KND balance, target band, 7-day flow in and out, suggested rebalance | Alert banners from treasury |
| Quotes | Latency, win rate, held quotes and reasons |  |
| Statements | Daily statement download (CSV and PDF) matching reconciliation format | Same format the partner uploads back |
| Developers | API keys, HMAC secret rotation, webhook endpoints and delivery log, sandbox switch | Rotation needs step-up |

## 5. Transparency page

A static site that reads the chain directly with a viem public client, so it works even if Kanda's backend is down; the indexer API is only used for history charts.

- Supply per chain and total (P2 adds Celo and Avalanche).
- Vault balance per leg, required backing per leg, coverage ratio per leg; P2 adds attested off-chain sleeves shown separately with attestation date.
- NAV with health badge, gold feed values and update times, basket version and quantities including G.
- Contracts: addresses, verified-source links, implementation versions.
- Governance: role holders, Safe thresholds, timelock queue with countdowns.
- History: supply and coverage over time; monthly attestation reports (P2).
- Every number has a link to the explorer or contract call that produced it.

## 6. Mobile app (P2)

- Expo React Native.
- Accounts: ERC-4337 modular smart accounts with passkey signing and guardian recovery behind a timelock, reusing the design already chosen for Asili Pay (modular account with a WebAuthn validation module, fallback PIN-encrypted local key).
- Gas sponsored by a paymaster for KND transfers within limits.
- Features: hold KND, see value in local currency, send KND to another Kanda user, cash out and top up through the country's partner (partner-hosted flows), payment history, receipts.
- Onboarding: phone number plus partner KYC; the account address is created at first use.

## 7. Admin console

| Area | Roles | Notes |
| --- | --- | --- |
| Corridors and limits | Ops | Changes above thresholds need a second approver |
| Partners and participants | Ops, compliance | Onboarding checklist from L4 |
| Intents | Ops, compliance | Search by any id, full trail export |
| Cases | Compliance | L4 section 6 workflow, second reviewer |
| Reconciliation | Ops, treasury | Breaks, owners, resolution |
| Safe proposals | Treasury | Prepares proposals and links to Safe; never holds keys |
| Emergency | Guardian members | Shows pause state and links to guardian Safe; the console cannot pause by itself |
| Audit log | All, read-only | Every admin action with before and after values |

## 8. Wallet interactions

- Partner lock: API returns unsigned calldata; the portal shows a human-readable summary (intent, amount, receiver partner, expiry) before the wallet prompt.
- Business self-custody transfers use EIP-3009 transferWithAuthorization so a relayer can pay gas; the signed message shows amount and recipient.
- Every write shows a pending state, then the finalized state from the indexer, never just the wallet's success callback.

## 9. Acceptance tests

- [ ] Playwright end-to-end: create payment, approve, fund (mock), lock, pay out, receipt, in sandbox
- [ ] Quote countdown expiry forces a new quote
- [ ] Transparency page renders with the backend turned off
- [ ] All screens usable at 360 px width and with Lighthouse accessibility score of 90 or more
- [ ] Locale switch changes number and currency formatting

## 10. Agent tasks

1. Build packages/ui with MoneyText, StatusTimeline, TxLink, CountdownBadge and the theme.
2. Generate packages/api-client from openapi.yaml.
3. Build apps/transparency first (P0), reading chain state only.
4. Build apps/partner inbox, lock and confirm payout screens.
5. Build apps/business new payment wizard and payment detail.
6. Build apps/admin with role guards, then cases and reconciliation screens.
7. P2: build apps/mobile on the passkey account stack.
