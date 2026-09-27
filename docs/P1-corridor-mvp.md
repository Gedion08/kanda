# P1 Corridor MVP

P1 puts KND on Base mainnet and runs real Kenya to Nigeria and Nigeria to Kenya business payments through two licensed partners, under hard caps. Exit after 30 consecutive days with zero unresolved reconciliation breaks and the pilot volume target met.

## Scope

| In | Out |
| --- | --- |
| KND, BasketVault, ParticipantRegistry, PaymentEscrow, NAVOracle, ZapRouter on Base mainnet | Other chains |
| Two independent audits, bug bounty | DEX liquidity incentives |
| Partner API, sandbox, webhooks, TypeScript SDK | Retail consumer app |
| Quote service, payment orchestrator, ledger, treasury, indexer, reconciliation | Off-chain reserves, cash desk |
| Screening, Travel Rule, case management, VABAS feed | On-chain FX oracle |
| Business web app, partner portal, admin console, transparency page | Mobile app |
| Pilot with 10 to 20 SMEs per side | Public marketing launch |

## Launch parameters (placeholders; set by timelock)

| Parameter | Value |
| --- | --- |
| Global supply cap | 1,000,000 KND |
| Participant tiers | Tier 1: 50,000 KND per day create and redeem; Tier 2: 250,000 |
| Create and redeem fee | 10 bps |
| Max single payment intent | 50,000 USD equivalent |
| Max per business per day | 100,000 USD equivalent |
| Escrow expiry | 4 hours from lock |
| Quote lock | 10 minutes |
| FX divergence hold threshold | 3% from reference (tune per corridor) |
| Finality depth for release | 12 Base blocks; wait for L1 batch inclusion above 25,000 USD |
| Timelock delay | 48 hours |

## Workstreams and deliverables

| Workstream | Deliverable | Done when | Spec |
| --- | --- | --- | --- |
| Contracts | PaymentEscrow, NAVOracle, ZapRouter; final registry and vault | Unit, fuzz, invariant, fork tests green | L1 |
| Contracts | Governance wiring on mainnet | Role map matches ADD section 4 exactly, verified by script | L1, L7 |
| Security | Audit 1 and audit 2, all highs and mediums fixed | Reports published | L7 |
| Oracles | Gold feed integration, off-chain FX reference service | Staleness and divergence alerts firing in staging | L2 |
| Backend | Gateway, quotes, orchestrator, ledger, treasury, indexer | End-to-end sandbox payment passes | L3 |
| Backend | Reconciliation job and report | Daily report with zero breaks in staging for 14 days | L3 |
| Compliance | Screening, Travel Rule, cases, VABAS export | Test cases pass, counsel sign-off | L4 |
| Apps | Business app, partner portal, admin console, transparency page | UAT signed by both partners | L5 |
| Partner API | OpenAPI spec, sandbox, SDK, docs | Both partners integrated in sandbox | L6 |
| Infra | Prod environment, MPC signer policies, monitoring, runbooks | Game day drill passed | L7 |
| Launch | Genesis ceremony, pilot onboarding, support rota | First live payment settled | This tab |

## Build order and milestones

1. M1 Contracts complete: PaymentEscrow and NAVOracle with tests; full invariant suite; code freeze for audit 1.
2. M2 Backend skeleton: database schema, gateway with idempotency, indexer on Base Sepolia, ledger with double-entry tests.
3. M3 Payment flow in sandbox: quote, intent, lock, confirm payout, release, refund on expiry, against mock partners.
4. M4 Compliance and apps: screening and Travel Rule in the flow; business app and partner portal usable end to end.
5. M5 Audit 2 and hardening: fix findings, game day, reconciliation clean for 14 days in staging.
6. M6 Mainnet: key ceremony, deploy, wire roles, verify, genesis create, pilot payments.

## Genesis ceremony

1. Record the gold reference price at a pre-announced block (median of two feeds); compute G = 0.30 / price, rounded to the vault's precision; publish it.
2. Deploy contracts with G in the basket config; verify source; transfer roles to Safes and timelock; renounce deployer roles.
3. Run the role verification script and publish its output.
4. First participant creates KND in kind; transparency page shows supply, vault balances and 100% or higher collateral ratio.

## Exit gate

- [ ] Both audits complete, findings resolved or accepted with rationale, reports public
- [ ] Bug bounty live
- [ ] 30 consecutive days with zero unresolved reconciliation breaks
- [ ] Pilot volume target met (placeholder 1M USD cumulative)
- [ ] All-in customer cost under 1.5% on median payment
- [ ] p95 on-chain leg under 60 seconds; p95 end to end under 30 minutes
- [ ] One pause and unpause drill and one expired-intent refund done on mainnet
- [ ] Regulator engagement log for Kenya and Nigeria up to date

## Risks in this phase

| Risk | Mitigation |
| --- | --- |
| Receiving partner pays out late or not at all | Escrow releases only on confirmation; partner SLA; collateral; offboarding path |
| Partner inventory imbalance (KND piles up in Nigeria) | Treasury alerts; partner redeems in kind or trades OTC with the other partner; inventory targets in partner agreement |
| Audit findings delay launch | Freeze scope early; keep P1 contracts small |
| Business users confused by KND's USD value moving | Show local currency first; disclosure at onboarding |

## Agent task pack

1. T1.1 Implement PaymentEscrow per L1 section 3.4 with unit tests for every state transition and revert.
2. T1.2 Implement NAVOracle per L1 section 3.5 and L2 section 2 with fork tests against Base.
3. T1.3 Implement ZapRouter per L1 section 3.6 with slippage and deadline tests.
4. T1.4 Extend the invariant suite with INV-4 and INV-5.
5. T1.5 Create the database schema per L3 section 4 with Drizzle migrations.
6. T1.6 Build the API gateway middleware per L3 section 3 (auth, HMAC, idempotency, rate limits).
7. T1.7 Build the Ponder indexer per L3 section 6.
8. T1.8 Build the payment orchestrator state machine per L3 section 5.
9. T1.9 Build the ledger module and posting rules per L3 section 7.
10. T1.10 Build the quote service per L2 section 4.
11. T1.11 Build reconciliation per L3 section 8.
12. T1.12 Integrate screening and Travel Rule per L4 sections 3 and 4.
13. T1.13 Build the partner portal, business app and admin console per L5.
14. T1.14 Publish the OpenAPI spec and generate the SDK per L6.
15. T1.15 Write runbooks and alerts per L7.
