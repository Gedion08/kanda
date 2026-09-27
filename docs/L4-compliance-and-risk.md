# L4 Compliance and risk

Compliance is built into every payment, not bolted on: each intent is screened, carries Travel Rule data before any KND moves, and leaves an audit trail a regulator can follow end to end. Licensed partners own customer KYC and fiat obligations; Kanda owns participant KYB, network screening, Travel Rule orchestration and token-level controls.

## 1. Who is responsible for what

| Obligation | Kanda issuer | Kanda network operator | Ramp partner |
| --- | --- | --- | --- |
| KYB of authorized participants | Owns |  |  |
| KYC or KYB of customers | Reviews reliance | Stores result and document references | Owns |
| Sanctions screening of parties |  | Owns per intent | Owns at onboarding |
| Wallet screening | Owns for primary market | Owns per intent | Own wallets |
| Travel Rule |  | Orchestrates | Originator and beneficiary VASP duties |
| Suspicious transaction reports | Issuer's reporting officer | Escalates to issuer and partners | Files in its country |
| Token blocklist | Owns |  |  |
| Fiat handling |  |  | Owns |

Before P1 go-live, appoint a money laundering reporting officer (hire or outsourced) and have counsel confirm this split in each corridor country.

## 2. Onboarding

Partners: licence verification, ownership and directors, AML programme review, sanctions screening of entity and owners, financial standing, security questionnaire, wallet ownership proof (signed message), signed partner agreement with SLAs, inventory bands and collateral.

Authorized participants: same as partners plus market-making history and source of funds for reserve assets.

Businesses (via onboarding partner, reliance model): registration documents, beneficial owners above 25% (or the local threshold), directors, address, expected corridor volume and purpose. Kanda stores the partner's KYB outcome, document hashes and risk rating.

| Business tier | Requirements | Limits (placeholders) |
| --- | --- | --- |
| T1 | Registration and one director verified | 10,000 USD per payment, 25,000 per day |
| T2 | Full UBO verification, trade documents | 50,000 USD per payment, 100,000 per day |
| T3 | Enhanced due diligence, site visit or bank reference | Negotiated |

## 3. Screening

| When | Who or what | Tool | Hit handling |
| --- | --- | --- | --- |
| Partner, participant, business onboarding | Entity, UBOs, directors | Sanctions, PEP and adverse media provider | Block onboarding pending review |
| Every intent | Originator, beneficiary, both businesses | Same provider | Intent to HELD, case opened |
| Every intent | Partner wallets, escrow counterparties | Blockchain analytics provider plus VABAS | Severe risk: HELD; moderate: flag |
| Primary market | Participant wallets and asset sources | Blockchain analytics provider | Create or redeem blocked by ops if severe |
| Daily | All active parties against list updates | Provider rescreen | New hit: freeze new intents, case |
| Continuous | All KND transfers | VABAS monitoring | Alerts per section 5 |

Screening results are stored with the list version, match score, reviewer and decision.

## 4. Travel Rule

- Every intent carries originator and beneficiary data in the IVMS101 data model: names, account or wallet identifiers, address or national ID or date of birth as the jurisdiction requires.
- Messages go from the sending partner to the receiving partner through a Travel Rule provider that interoperates with common protocols; Kanda triggers the exchange at FUNDED and blocks lock until the receiving partner accepts.
- The on-chain metadataHash = keccak256(canonical JSON of the IVMS101 payload, invoice reference and a random 32-byte salt). The salt stops anyone brute-forcing names from the hash; the payload and salt stay encrypted off-chain.

## 5. Transaction monitoring rules (starting set)

| Rule | Signal | Threshold (placeholder) | Action |
| --- | --- | --- | --- |
| Structuring | Several payments just under a tier limit | 3 within 7 days at over 90% of limit | Case |
| Velocity | Payment count or value spike vs 30-day baseline | Over 3x baseline | Case |
| New beneficiary, high value | First payment to a beneficiary | Over 50% of per-payment limit | Hold for approval |
| Invoice mismatch | Payment amount vs attached invoice | Differs by over 10% | Case |
| Circular flows | Funds returning to originator through the corridor | Any within 30 days | Case |
| High-risk wallet exposure | Partner or holder wallet exposure to sanctioned or illicit clusters | Provider severe category | Hold and escalate |
| Rapid in-out on KND | Holder receives and sends out within minutes, repeatedly | 5 times in 24 h | Alert |
| Dormant reactivation | No activity for 180 days, then large payment | Over T1 limit | Case |

## 6. Case management

- States: Open, Investigating, Escalated, Closed cleared, Closed reported.
- Every case has owner, SLA (24 h for held payments, 5 days otherwise), linked intents, evidence, decision and a second reviewer for closure.
- Closed reported cases record the report reference filed by the responsible entity.
- Retention: at least 7 years; cases are append-only.

## 7. On-chain controls

- Blocklist use only on a legal instruction or a confirmed sanctions match under the issuer's jurisdiction; two Compliance Safe signers; public event; internal record of the legal basis.
- Target: sanctioned addresses blocked within 24 hours of list publication.
- Unblocking follows the same process.
- No seize or burn of blocked funds in P1; revisit with counsel before P2.

## 8. Data protection

- PII lives only in the compliance schema with field-level envelope encryption (KMS keys per region); other schemas reference it by id.
- Data minimisation: store document hashes and provider references, not document copies, unless a regulator requires copies.
- Residency: keep each country's customer data in the region its law requires; confirm Kenya and Nigeria requirements in P0.
- Data subject requests handled within legal deadlines; AML retention overrides deletion, and the response says so.

## 9. VABAS integration

VABAS consumes Kanda's event stream (on-chain events, intent transitions, screening outcomes without PII) for multi-chain flow analytics, cluster risk and regulator-ready exports. Its risk scores feed back into wallet screening as a second opinion alongside the commercial provider.

## 10. Financial risk controls

| Risk | Metric | Limit (placeholder) |
| --- | --- | --- |
| Reserve concentration (P2) | Share of USD leg with one custodian or token | Under 60% |
| Gold instrument concentration (P2) | Share of gold leg in one token | Under 70% |
| Partner exposure | KND in escrow per receiving partner | Under partner collateral times 3 |
| Partner inventory | Inventory outside target band | Alert at 20% outside, pause corridor at 50% |
| Liquidity | On-chain vault sleeve vs 7-day redemption peak (P2) | Over 150% |

## 11. Regulatory reporting

- Monthly: volumes per corridor, rate basis used, held and reported cases, reserve composition.
- On demand: full trail for an intent (quote, screening, Travel Rule, on-chain transactions, payout reference).
- Regulator read-only dashboard in P2.

## 12. Compliance schema

```sql
create schema compliance;

create table compliance.parties (
  id uuid primary key, kind text not null check (kind in ('person','entity')),
  encrypted_pii bytea not null, pii_key_id text not null,
  country char(2), risk_rating text, created_at timestamptz not null default now()
);

create table compliance.screenings (
  id uuid primary key, subject_type text not null, subject_id text not null,
  provider text not null, list_version text, result text not null,
  score numeric(5,2), raw_ref text, reviewed_by uuid, decision text,
  created_at timestamptz not null default now()
);

create table compliance.travel_rule_messages (
  id uuid primary key, intent_id uuid not null, provider_ref text,
  status text not null check (status in ('sent','accepted','rejected','expired')),
  payload_hash bytea not null, encrypted_payload bytea not null,
  created_at timestamptz not null default now()
);

create table compliance.cases (
  id uuid primary key, status text not null, rule text not null,
  owner uuid, second_reviewer uuid, sla_due timestamptz not null,
  decision text, report_reference text,
  created_at timestamptz not null default now()
);

create table compliance.case_links (
  case_id uuid not null references compliance.cases(id),
  ref_type text not null, ref_id text not null,
  primary key (case_id, ref_type, ref_id)
);
```

## 13. Acceptance tests

- [ ] A sanctioned test name moves an intent to HELD and blocks lock
- [ ] A severe-risk test wallet blocks the intent
- [ ] Lock cannot happen before the Travel Rule message is accepted
- [ ] metadataHash on-chain matches the stored payload and salt
- [ ] Case closure requires a second reviewer
- [ ] PII never appears in logs (log scrubber test)

## 14. Agent tasks

1. Build the compliance module with provider adapters behind interfaces (ScreeningProvider, WalletRiskProvider, TravelRuleProvider) and a mock for each.
2. Implement the compliance schema, envelope encryption helper and log scrubber.
3. Wire screening and Travel Rule gates into the payment state machine.
4. Implement monitoring rules as a rules table evaluated by a worker; each rule unit-tested.
5. Build the case management screens in the admin console (L5).
6. Build the VABAS export as an outbox consumer.
