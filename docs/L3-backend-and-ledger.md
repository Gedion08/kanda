# L3 Backend and ledger

The backend is a TypeScript modular monolith that orchestrates payments, keeps a double-entry ledger and reconciles it daily against the chain and partner statements. Kanda never custodies customer fiat or customer KND in P1: partners hold their own wallets, and Kanda's only signing key can release escrowed intents.

## 1. Stack and structure

- Node 22, TypeScript strict, Hono for HTTP, zod for validation, Drizzle ORM with Postgres 16, Redis, BullMQ, viem, pino logs, OpenTelemetry.
- Ponder as a separate app for indexing.
- Money: every amount is a string on the wire and a bigint in code. KND base units exceed Postgres bigint (18 decimals), so store amounts as numeric(78,0) in base units, never floats.

```
apps/
  api/            Hono server: gateway + modules
    src/modules/{auth,partners,businesses,quotes,payments,ledger,treasury,compliance,webhooks,admin}
    src/jobs/     BullMQ workers
  indexer/        Ponder
packages/
  db/             Drizzle schema and migrations
  chain/          ABIs, addresses, viem clients, tx submitter
  pricing/        fixed-point math, NAV, quotes (L2)
  sdk/            partner SDK (L6)
  shared/         types, errors, money helpers
```

## 2. Modules

| Module | Owns | Talks to |
| --- | --- | --- |
| auth | Partner keys, HMAC, user sessions, WebAuthn step-up | all |
| partners | Partner records, wallets, quote endpoints, SLAs | quotes, payments |
| businesses | KYB records (via L4), users, roles, approval policies | compliance |
| quotes | Quote lifecycle (L2) | partners, pricing |
| payments | Intent state machine | quotes, compliance, chain, webhooks, ledger |
| ledger | Double-entry postings, balances | payments, treasury, recon |
| treasury | Inventory monitoring, vault ops proposals, fee sweeps | chain, ledger |
| compliance | Screening, Travel Rule, cases (L4) | payments, businesses |
| webhooks | Outbound events with signing and retries | partners |
| admin | Limits, corridor switches, recon views, audit log | all |

## 3. API gateway

- Partners: API key id plus HMAC-SHA256 signature over method, path, timestamp, body hash; reject if the timestamp is more than 300 s off; optional mTLS and IP allowlist.
- Business users: OIDC session; sensitive actions (approve payment, add beneficiary, change limits) require WebAuthn step-up.
- Idempotency: every POST requires Idempotency-Key; store key, principal, request hash and response for 24 h; same key with a different body returns 409.
- Rate limits: Redis token bucket per principal and per route.
- Errors: RFC 9457 problem+json with a stable code field.
- Every request logged with principal, route, status, latency, trace id; admin actions also go to the append-only audit log.

## 4. Database schema (core)

```sql
create table partners (
  id uuid primary key, name text not null, country char(2) not null,
  kind text not null check (kind in ('ramp','market_maker')),
  status text not null check (status in ('onboarding','active','suspended','offboarded')),
  wallet_address text not null, quote_endpoint text, webhook_url text,
  api_key_id text unique not null, hmac_secret_ref text not null,
  created_at timestamptz not null default now()
);

create table businesses (
  id uuid primary key, legal_name text not null, country char(2) not null,
  registration_no text not null, kyb_status text not null,
  onboarding_partner_id uuid references partners(id),
  created_at timestamptz not null default now()
);

create table users (
  id uuid primary key, business_id uuid references businesses(id),
  email text unique not null,
  role text not null check (role in ('maker','approver','viewer','admin')),
  created_at timestamptz not null default now()
);

create table corridors (
  id text primary key,                     -- e.g. KE-NG
  send_currency char(3) not null, receive_currency char(3) not null,
  send_partner_id uuid not null references partners(id),
  receive_partner_id uuid not null references partners(id),
  status text not null check (status in ('open','paused','closed')),
  max_intent_usd numeric(20,2) not null, divergence_bps int not null
);

create table quotes (
  id text primary key, corridor_id text not null references corridors(id),
  business_id uuid not null references businesses(id),
  send_minor numeric(38,0) not null, receive_minor numeric(38,0) not null,
  knd_amount numeric(78,0) not null,
  rates jsonb not null, fees jsonb not null, rate_basis jsonb not null,
  partner_quote_ids jsonb not null,
  status text not null check (status in ('locked','held','confirmed','expired','rejected')),
  expires_at timestamptz not null, created_at timestamptz not null default now()
);

create table payment_intents (
  id uuid primary key, onchain_id bytea unique not null,
  quote_id text unique not null references quotes(id),
  business_id uuid not null references businesses(id),
  beneficiary_ref uuid not null,            -- encrypted PII lives in compliance schema
  sender_partner_id uuid not null references partners(id),
  receiver_partner_id uuid not null references partners(id),
  knd_amount numeric(78,0) not null, status text not null,
  escrow_expiry timestamptz, metadata_hash bytea,
  lock_tx bytea, release_tx bytea, refund_tx bytea, payout_reference text,
  version int not null default 0,           -- optimistic locking
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table intent_events (
  id bigserial primary key, intent_id uuid not null references payment_intents(id),
  from_status text, to_status text not null, trigger text not null,
  actor text not null, payload jsonb, created_at timestamptz not null default now()
);

create table ledger_accounts (
  id uuid primary key, code text unique not null, asset text not null,
  kind text not null check (kind in ('asset','liability','revenue','expense','memo'))
);

create table ledger_transactions (
  id uuid primary key, ref_type text not null, ref_id text not null,
  posted_at timestamptz not null default now(), description text,
  unique (ref_type, ref_id)
);

create table ledger_entries (
  id bigserial primary key, tx_id uuid not null references ledger_transactions(id),
  account_id uuid not null references ledger_accounts(id),
  direction char(1) not null check (direction in ('D','C')),
  amount numeric(78,0) not null check (amount > 0), asset text not null
);

create table onchain_events (
  chain_id int not null, block_number bigint not null, tx_hash bytea not null,
  log_index int not null, contract text not null, event text not null,
  args jsonb not null, finalized boolean not null default false,
  primary key (chain_id, tx_hash, log_index)
);

create table outbox (
  id bigserial primary key, topic text not null, payload jsonb not null,
  created_at timestamptz not null default now(), published_at timestamptz
);

create table idempotency_keys (
  principal text not null, key text not null, request_hash text not null,
  response jsonb, created_at timestamptz not null default now(),
  primary key (principal, key)
);
```

A deferred constraint trigger rejects any ledger transaction whose debits and credits differ per asset. Ledger tables and intent\_events allow insert only; the application role has no update or delete grant on them.

## 5. Payment orchestrator

&#91;embedded content: payment intent states · 5 main, 5 exceptional\]

| From | Trigger | To | Guard | Side effects |
| --- | --- | --- | --- | --- |
| (new) | Approver confirms locked quote | CONFIRMED | Quote not expired; approval policy met | Create intent; run screening |
| CONFIRMED | Screening hit | HELD |  | Open case (L4) |
| HELD | Case cleared | CONFIRMED |  | Resume |
| HELD | Case rejected | CANCELLED |  | Notify business |
| CONFIRMED | Funding instructions issued | AWAITING\_FUNDS |  | Partner A payment details to business |
| AWAITING\_FUNDS | Partner A confirmFunding | FUNDED | Amount within tolerance | Travel Rule message to Partner B |
| AWAITING\_FUNDS | 2 h timeout | CANCELLED |  | Notify |
| FUNDED | Partner A submits lock | LOCKING |  | Return unsigned lock tx via API |
| LOCKING | Locked event, finalized | LOCKED | Amount, receiver, hash match | Webhook intent.locked to Partner B |
| LOCKED | Partner B confirmPayout | PAID\_OUT | Payout reference present | Submit release |
| PAID\_OUT | Release submitted | RELEASING |  |  |
| RELEASING | Released event, finalized | COMPLETED |  | Ledger postings, receipts, fee accrual |
| LOCKED | Rejected by Partner B, or expiry passed | REFUNDING, then REFUNDED |  | Refund tx; Partner A refunds customer fiat |
| LOCKED | Disputed event | DISPUTED |  | Case |
| DISPUTED | Resolved event | RESOLVED |  | Ledger split postings |

Rules:

- Every transition is one Postgres transaction: update intent with version check, insert intent\_events row, insert outbox row.
- Chain-driven transitions only fire from finalized onchain\_events rows.
- Timeouts are delayed BullMQ jobs keyed by intent id and target state; a job that finds the state already moved is a no-op.
- Kanda's releaser key (MPC) signs release only for intents in PAID\_OUT with a matching payout reference; the signer policy re-checks this against the API.

## 6. Indexer

- Ponder app indexing KandaToken, BasketVault, ParticipantRegistry, PaymentEscrow and, in P2, CCIP pools, per chain, from deployment blocks in deployments/\<network>.json.
- Handlers write raw events to onchain\_events and typed tables (supply, vault legs, intents).
- Finality: a worker marks rows finalized when their block is at or below the RPC safe block; releases above 25,000 USD wait for the finalized block.
- Reorg: Ponder rewinds; rows not yet finalized are deleted and re-inserted; the orchestrator never acted on them.

## 7. Ledger

Chart of accounts (per asset):

| Code | Kind | Meaning |
| --- | --- | --- |
| vault:reserve:{asset} | asset | Reserves held in BasketVault |
| knd:supply | liability | KND in circulation |
| escrow:locked | asset | KND locked in PaymentEscrow |
| partner:{id}:committed | liability | KND a partner has committed to escrow |
| partner:{id}:received | memo | KND received by a receiving partner |
| partner:{id}:fees\_receivable | asset | Network fees owed by partner (invoiced monthly in P1) |
| revenue:network\_fees | revenue | Network fee income |
| revenue:vault\_fees | revenue | Create and redeem fees |

Posting rules:

| Event | Debit | Credit |
| --- | --- | --- |
| Created (vault) | vault:reserve per leg | knd:supply |
| Redeemed (vault) | knd:supply | vault:reserve per leg |
| Locked | escrow:locked | partner:A:committed |
| Released | partner:A:committed | escrow:locked (and memo to partner:B:received) |
| Refunded | partner:A:committed | escrow:locked |
| Completed, fee accrual | partner:A:fees\_receivable | revenue:network\_fees |

Decision recorded: in P1 network fees are invoiced monthly rather than taken in-contract, keeping PaymentEscrow minimal.

## 8. Reconciliation

Daily close at 00:00 UTC plus an hourly light run.

| Check | Compare | Break type |
| --- | --- | --- |
| Escrow | escrow:locked vs KND balanceOf(PaymentEscrow) | Amount mismatch |
| Vault | vault:reserve per leg vs on-chain balances | Amount mismatch |
| Supply | knd:supply vs totalSupply | Amount mismatch |
| Intents | every non-terminal intent vs on-chain status | Status mismatch |
| Orphans | on-chain events with no intent, intents with no event past SLA | Orphan |
| Partners | partner daily statements (fiat in, fiat out, references) vs intents | Statement mismatch |
| Cross-chain (P2) | Base lock pool vs sum of remote supplies | Supply mismatch |

Each break becomes a recon\_breaks row with owner, severity and resolution note; an unresolved break older than 24 h pages on-call and blocks raising any limit.

## 9. Treasury

- Watches each partner's KND inventory against target bands in the partner agreement; alerts both partners and ops on breach.
- Prepares Safe transaction proposals (never executes) for vault parameter changes, fee sweeps and participant limits.
- Tracks vault coverage per leg every block from the indexer and pages if any leg falls below 100%.

## 10. Outbound webhooks

Events: quote.held, intent.confirmed, intent.funded, intent.locked, intent.paid\_out, intent.completed, intent.refunded, intent.disputed, intent.resolved, partner.inventory\_low. Signed with HMAC-SHA256 plus timestamp; at-least-once delivery with exponential backoff for 24 h; consumers dedupe by event id; ordering per intent guaranteed by sequence number.

## 11. Transaction submission

One submitter service per signing key: nonce manager in Postgres, EIP-1559 gas with a cap, replacement of stuck transactions after 3 blocks, idempotent by intent id so a retry never double-submits. Partner-signed transactions (lock) are built by the API and returned unsigned; the SDK signs with the partner's own key.

## 12. Acceptance tests

- [ ] Happy path Kenya to Nigeria in sandbox end to end with mock partners
- [ ] Expired intent refunds without any Kanda service running (permissionless refund)
- [ ] Duplicate API calls with the same idempotency key return the same result
- [ ] Killing the worker mid-transition leaves no half-applied state
- [ ] Reorg simulation on Anvil does not trigger any release
- [ ] Reconciliation catches an injected escrow mismatch within one hourly run

## 13. Agent tasks

1. Scaffold apps/api with Hono, zod, pino, OpenTelemetry and the problem+json error handler.
2. Implement packages/db with the schema above and the ledger balance trigger.
3. Implement auth: partner HMAC, idempotency middleware, rate limiter.
4. Implement the payments module with the transition table as data, not scattered if-statements; generate tests from the table.
5. Implement apps/indexer with Ponder and the finality worker.
6. Implement the ledger module and posting rules with property tests (balanced per asset).
7. Implement reconciliation and the break workflow.
8. Implement webhooks with the outbox relay.
9. Implement the transaction submitter with a local signer for dev and the MPC adapter for staging and prod.
