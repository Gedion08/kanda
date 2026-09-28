# Architecture Design

Kanda is four layers: clients, off-chain Kanda services, contracts on Base, and external providers. Only the contracts hold value; every off-chain service can fail without putting reserves at risk. This tab is the canonical architecture; each layer tab specifies one layer in build-ready detail.

## 1. Principles

1. Value lives only in contracts. Services orchestrate, index and sign within narrow limits; none can mint or move reserves alone.
2. No oracle in the mint and burn path. Primary market is in kind; prices are only used for display, quotes, zaps and pools.
3. Kanda never sets a local FX rate. Licensed partners quote their own currency; Kanda checks quotes against a reference and holds outliers.
4. Personal data never goes on-chain. Contracts see addresses, amounts and hashes only.
5. Every state change is idempotent and reconcilable: chain, ledger and partner statements must agree daily.
6. Caps first, then growth. Supply caps, participant limits and corridor limits ship on day one and are raised by governance.
7. Fast to stop, slow to change. Pause is one call away; upgrades and parameter changes wait 48 hours in a public timelock.
8. Reuse proven parts: OpenZeppelin, Safe, Chainlink, Uniswap v4. Write custom code only where Kanda is different.

## 2. System context

&#91;embedded content: Kanda system context · 4 layers\]

Clients call Kanda services; services send transactions and read events; external ramps, reserve assets and price feeds touch the contracts directly, and ramps also call the Partner API (left line).

## 3. Component catalogue

| Component | Layer | Responsibility | Tech | Phase | Spec tab |
| --- | --- | --- | --- | --- | --- |
| KND token | Contracts | ERC-20, permit, EIP-3009, blocklist, pause | Solidity, OZ upgradeable v5, UUPS | P1 | L1 |
| BasketVault | Contracts | Holds reserves; in-kind create and redeem; enforces caps | Solidity | P1 | L1 |
| ParticipantRegistry | Contracts | Allowlist of authorized participants, tiers, daily limits | Solidity | P1 | L1 |
| PaymentEscrow | Contracts | Locks KND per payment intent; release, refund, dispute | Solidity | P1 | L1 |
| NAVOracle | Contracts | NAV in USD from gold feed with staleness and deviation guards | Solidity, Chainlink | P1 | L1, L2 |
| ZapRouter | Contracts | USDC-only create via swap of gold leg with slippage bound | Solidity | P1 | L1 |
| FXReferenceOracle | Contracts | Signed partner and public FX rates, median, divergence flags | Solidity | P2 | L2 |
| Hub pools and hooks | Contracts | Uniswap v4 pools with OracleBandHook and optional AllowlistHook | Solidity | P2 | L1, L2 |
| RFQSettler | Contracts | Settles EIP-712 signed market-maker quotes | Solidity | P2 | L1 |
| CCIP token pools | Contracts | Burn and mint across chains with rate limits | Chainlink CCIP | P2 | L1 |
| Governance | Contracts | Safes, TimelockController, role wiring | Safe, OZ | P1 | L1, L7 |
| API gateway | Services | Auth, rate limits, idempotency, request signing | Hono on Node | P1 | L3, L6 |
| Quote service | Services | Collects partner quotes, composes all-in quote, locks it | TypeScript, Redis | P1 | L2, L3 |
| Payment orchestrator | Services | Payment intent state machine, partner webhooks, timeouts | TypeScript, BullMQ, Postgres | P1 | L3 |
| Ledger | Services | Double-entry books per partner, customer and corridor | Postgres | P1 | L3 |
| Treasury | Services | Vault operations, inventory monitoring, rebalancing alerts | TypeScript, viem | P1 | L3 |
| Compliance | Services | Screening, Travel Rule, cases, reporting, VABAS feed | TypeScript, providers | P1 | L4 |
| Indexer | Services | Chain events into Postgres with finality tracking | Ponder | P1 | L3 |
| MPC signer | Services | Operational keys with policy engine | Turnkey or Fireblocks | P1 | L7 |
| Business app, partner portal, admin console | Clients | Web UIs | React, Vite, wagmi, viem, RainbowKit, shadcn/ui | P1 | L5 |
| Transparency page | Clients | Public supply, reserves, NAV | React, static hosting | P1 | L5 |
| Mobile app | Clients | Passkey smart accounts for businesses and individuals | Expo, ERC-4337 | P2 | L5 |
| Partner API and SDK | Clients | REST, webhooks, TypeScript SDK | OpenAPI 3.1 | P1 | L6 |

## 4. On-chain architecture

### Contracts and ownership

| Role | Held by | Can do |
| --- | --- | --- |
| DEFAULT\_ADMIN\_ROLE | TimelockController (48 h), proposer: Admin Safe 3 of 5 | Grant and revoke roles |
| UPGRADER\_ROLE | TimelockController | Upgrade UUPS proxies |
| LIMITS\_ADMIN\_ROLE | TimelockController | Set supply cap, tier caps, fees, basket version |
| MINTER\_ROLE on KND | BasketVault; in P2 also CCIP pool and CashDesk | Mint and burn |
| PAUSER\_ROLE | Guardian Safe 2 of 4 and a pause-only monitoring bot key | Pause KandaToken, BasketVault or PaymentEscrow; pause creation only on BasketVault |
| UNPAUSER\_ROLE | Admin Safe 3 of 5 | Unpause, including creation on BasketVault |
| COMPLIANCE\_ROLE | Compliance Safe 2 of 3 | Block and unblock addresses |
| PARTICIPANT\_MANAGER\_ROLE | Ops Safe 2 of 3 | Add participants and set limits within tier caps |
| ARBITER\_ROLE | Ops Safe 2 of 3 | Resolve disputed escrow intents |
| RELEASER\_ROLE | Releaser MPC key with release-only policy (L7 section 2) | Release Locked escrow intents |
| LIMITS\_CONSUMER\_ROLE | BasketVault; in P2 also CashDesk | Consume participants' daily create and redeem limits in ParticipantRegistry |
| ORACLE\_ADMIN\_ROLE | TimelockController | Change feeds and thresholds |

### System invariants

These must hold after every transaction and are encoded as Foundry invariant tests (L1).

- INV-1 Full backing: for each basket asset, vault balance is at least totalSupply times the per-unit quantity, rounded up.
- INV-2 totalSupply is at or below the supply cap.
- INV-3 Only addresses with MINTER\_ROLE change totalSupply.
- INV-4 PaymentEscrow's KND balance equals the sum of amounts in Locked and Disputed intents.
- INV-5 A Released or Refunded intent never changes state again.
- INV-6 No participant exceeds its daily create or redeem limit.
- INV-7 While KandaToken is paused, no transfer, create, redeem, lock, release or refund succeeds. While BasketVault is paused, no create or redeem succeeds; while only its creation is paused, no create succeeds and redeem continues. While PaymentEscrow is paused, none of its state-changing functions succeeds.
- INV-8 A blocked address can neither send nor receive KND.

### Upgrade model

KND, BasketVault, ParticipantRegistry and PaymentEscrow are UUPS proxies. Upgrades go through the timelock with a 48-hour delay and a published diff. NAVOracle and ZapRouter are non-upgradeable and replaced by redeploy plus role change. Storage uses ERC-7201 namespaced layouts.

## 5. Money flows

### Create and redeem in kind

1. Participant approves USDC and DGLD to BasketVault (USDC also accepts permit; DGLD has no permit).
2. Participant calls createInKind(amount, to). The vault computes each asset's quantity rounded up, pulls it, measures the balance delta to handle fee-on-transfer, applies the fee, checks caps and limits, and mints KND.
3. Redeem burns KND first, then sends each asset's quantity rounded down, minus the fee.

### Kenya to Nigeria payment

1. Business requests a quote; Quote service fetches Partner A's KES per KND and Partner B's NGN per KND, checks both against the FX reference, and returns an all-in quote with a 10-minute lock.
2. Business confirms; Payment orchestrator creates intent INT-x in Postgres and emits a Travel Rule message from Partner A to Partner B.
3. Business pays KES to Partner A; Partner A calls confirmFunding via the API.
4. Partner A's wallet calls PaymentEscrow.lock(intentId, amount, receiverPartner, expiry, metadataHash).
5. Indexer sees Locked after the finality depth; orchestrator notifies Partner B by webhook.
6. Partner B pays NGN to the supplier and calls confirmPayout with its bank reference.
7. Orchestrator (via MPC signer, release-only policy) or Partner A calls release; escrow sends KND to Partner B.
8. Ledger posts entries; both businesses receive receipts.

If step 6 does not happen before expiry, anyone can call refund after expiry and the KND returns to Partner A.

### Quote composition

```latex
R_{NGN} = \frac{S_{KES} - F_A}{r_A} \cdot (1 - f_{net}) \cdot r_B - F_B
```

S is the send amount, F are partner fixed fees, r\_A is Partner A's KES per KND (buy), r\_B is Partner B's NGN per KND (sell), f\_net is the Kanda network fee.

## 6. Off-chain architecture

- Modular monolith in Phase 1: one Hono service with modules for gateway, quotes, payments, ledger, treasury and compliance, one Postgres, one Redis. Split into services only when load or team size requires it.
- Durable jobs through BullMQ with explicit state machines stored in Postgres; migrate long-running workflows to Temporal in P2 if timeouts and retries grow complex.
- Ponder indexes contract events into its own schema; the orchestrator reads only events past the finality depth (Base: wait for L1 batch posting for releases above a threshold, 12 L2 blocks otherwise; confirm in P0).
- Every inbound API call carries an Idempotency-Key; every outbound transaction is keyed by intent id so retries cannot double-lock.
- Outbox pattern: state change and outgoing event are written in one Postgres transaction and published by a relay.

## 7. Data architecture

| Data | Where | Why |
| --- | --- | --- |
| Balances, supply, reserves, intents' amounts and states | Chain | Source of truth for value |
| Payment intents, quotes, customers, partners | Postgres | Business state, PII |
| Double-entry ledger | Postgres, append-only | Accounting and reconciliation |
| Travel Rule payloads | Encrypted in Postgres; hash on-chain | Privacy with verifiability |
| Screening results, cases | Postgres, compliance schema | Audit |
| Quotes cache, rate limits | Redis | Latency |
| Analytics | VABAS feed | Monitoring and regulator reporting |

## 8. Oracles and pricing

- NAV: 0.70 + G times XAU/USD, from Chainlink XAU/USD on Base (primary) and Chainlink PAXG/USD (secondary), with a staleness limit and a maximum deviation between feeds (ADR-010). Used for display, zap bounds and pool bands.
- FX reference (P1 off-chain, P2 on-chain): median of partner quotes plus published official rates. Each corridor has a divergence threshold; a quote outside it is held, not auto-rejected, so the partner can explain parallel-market conditions.
- Partners own their local rate; Kanda records which rate the partner declared (official or market) for regulator reporting.

## 9. Security architecture

| Asset | Threat | Control |
| --- | --- | --- |
| Reserves in vault | Contract bug | Audits, invariants, caps, pause, bounty |
| Mint authority | Compromised admin | Only the vault mints; vault logic cannot mint unbacked |
| Upgrades | Malicious upgrade | Timelock 48 h, 3 of 5 Safe, public monitoring of queue |
| Escrow release key | Hot key theft | MPC policy: release only for intents confirmed by Partner B, amount limits |
| Partner API | Credential theft | mTLS or HMAC-signed requests, IP allowlists, short-lived tokens |
| Quotes | Manipulated partner rate | Reference divergence holds, per-partner limits |
| PII | Breach | Field encryption, least privilege, residency, no PII on-chain |
| Ops console | Insider abuse | SSO with hardware keys, four-eyes on sensitive actions, audit log |

## 10. Compliance architecture

Screening runs at four points: partner onboarding, participant onboarding, every intent (both parties and wallets), and continuous monitoring of KND flows. Travel Rule messages go partner to partner through a provider before lock. Alerts become cases with an owner, SLA and outcome. On-chain blocking is a last resort used on legal instruction. VABAS consumes the event stream for multi-chain analytics and regulator exports.

## 11. Cross-chain (Phase 2)

KND moves between Base, Celo and Avalanche through Chainlink CCIP burn-and-mint token pools. Base stays the home chain holding the vault; other chains hold only bridged supply. Per-lane rate limits cap exposure; the transparency page shows supply per chain and reconciles it to the vault.

## 12. Environments

| Env | Chain | Purpose |
| --- | --- | --- |
| local | Anvil fork of Base | Development and invariant tests |
| dev | Base Sepolia | Integration with mock partners |
| staging | Base Sepolia | Partner sandbox, release candidates |
| prod | Base mainnet | Live, capped |

Off-chain hosting: a cloud region in Africa (for example AWS Cape Town) subject to each country's data residency rules; confirm with counsel in P0.

## 13. Observability

OpenTelemetry traces across API, jobs and chain calls; metrics for quote latency, intent age by state, escrow balance vs ledger, collateral ratio, oracle staleness; Sentry for errors; Tenderly or equivalent alerts on role changes, timelock queue, pauses and large mints; an invariant watcher that recomputes INV-1 and INV-4 every block and pages on failure.

## 14. Tech stack

| Area | Choice | Note |
| --- | --- | --- |
| Contracts | Solidity 0.8.28, Foundry, OpenZeppelin upgradeable v5 | Invariant and fork tests |
| Governance | Safe, TimelockController |  |
| Indexer | Ponder | Postgres-native, viem-based |
| Backend | TypeScript, Hono, Drizzle ORM, Postgres 16, Redis, BullMQ, viem | Same family as the Asili Pay backend |
| Frontend | React, Vite, wagmi 2, viem, RainbowKit, shadcn/ui, TanStack Query | Reuses Asili Pay frontend patterns |
| Mobile (P2) | Expo, ERC-4337 modular accounts with passkeys | Reuse the Asili Pay passkey account design |
| Keys | Turnkey or Fireblocks | Decide in P0 |
| Monorepo | pnpm, Turborepo |  |
| Infra | Terraform, GitHub Actions, containers |  |

## 15. Architecture decision records

| ADR | Decision | Status |
| --- | --- | --- |
| 001 | Fixed-quantity basket, 70 USD / 30 gold | Accepted |
| 002 | In-kind primary market, no oracle in mint path | Accepted |
| 003 | Base as home chain | Accepted |
| 004 | Blocklist, not allowlist, on the token | Accepted |
| 005 | Partners own local FX rates | Accepted |
| 006 | UUPS proxies behind a 48-hour timelock | Accepted |
| 007 | Ponder over The Graph for the operational indexer | Proposed |
| 008 | BullMQ in P1, Temporal considered in P2 | Proposed |
| 009 | MPC provider | Open |
| 010 | DGLD as the Phase 1 gold leg on Base; Chainlink XAU/USD primary and PAXG/USD secondary gold feeds (details in L1 section 4, L2 section 2) | Accepted |
| 011 | Pause model: KandaToken pause stops all KND movement; BasketVault and PaymentEscrow each have their own pause; BasketVault can pause creation alone so redeem stays open | Accepted |
| 012 | setBasket deferred to P3; the P1 genesis basket is fixed in the BasketVault initializer | Accepted |
| 013 | MIT licence for all code in the repository | Accepted |

## 16. Failure modes

| Failure | Effect | Designed response |
| --- | --- | --- |
| Gold feed stale | NAV display frozen | Banner, zap disabled; in-kind create and redeem unaffected |
| Receiving partner offline | Intents stall | Expiry and permissionless refund; route to backup partner in P2 |
| Base sequencer outage | No transactions | Stop quoting, queue intents, resume on recovery |
| USDC depeg | Basket value drops | pauseCreate on BasketVault, KandaToken left unpaused; redeem continues in kind so holders exit with the actual assets |
| DGLD issuer pauses the token or blacklists the vault | Gold leg stuck: every create and redeem reverts because each moves every leg; a blacklisted vault's DGLD can be moved to the issuer's recovery address | Pause BasketVault, legal escalation with Gold Token SA; alert on DGLD Paused, Blacklisted, RecoveryFromBlacklistedAddress and Upgraded events; P2 diversifies across two gold tokens |
| Kanda backend down | No new payments | Funds safe on-chain; escrow expiry refunds |
| Indexer lag | Late notifications | No release before finality; reconciliation waits |
