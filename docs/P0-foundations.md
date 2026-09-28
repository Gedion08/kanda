# P0 Foundations

P0 turns Kanda from an idea into a licensable, partner-backed project with KND and BasketVault running on Base Sepolia. Exit when counsel has opined on KND's classification, two ramp partners have signed LOIs, and the testnet vault passes its invariant suite.

## Scope

| In | Out |
| --- | --- |
| Entity, counsel, jurisdiction memo, token classification opinion | Mainnet deployment |
| Partner LOIs for Kenya and Nigeria | Real customer funds |
| Basket parameters and gold instrument decision | Payment escrow in production |
| KND, BasketVault, ParticipantRegistry on Base Sepolia | Apps beyond a transparency prototype |
| Monorepo, CI, threat model, ADRs 007 to 010 | Cross-chain, FX pools |
| Compliance policy draft, provider shortlist |  |

## Workstreams and deliverables

| Workstream | Deliverable | Done when | Spec |
| --- | --- | --- | --- |
| Legal | Jurisdiction memo comparing 3 candidates | Issuer jurisdiction chosen | PSD section 11 |
| Legal | Token classification opinion (issuer country, Kenya, Nigeria) | Written opinion received | PSD section 11 |
| Legal | Draft terms: KND terms, participant agreement, partner agreement | Drafts ready for partner review | L6 |
| Partners | Partner requirements doc (licences, API, SLAs, collateral) | Sent to candidates | L6 |
| Partners | Signed LOIs, one Kenyan and one Nigerian ramp | Both signed | PSD section 13 |
| Basket | Basket spec v1: split, G formula, genesis procedure, reconstitution rule | Signed off | PSD section 5, L1 |
| Basket | Gold instrument decision: DGLD chosen 27 Sep 2026 | ADR-010 accepted | L1 |
| Tech | Monorepo, CI, linting, contract test harness | Green pipeline on main | Build Playbook |
| Tech | KND, BasketVault, ParticipantRegistry on Base Sepolia | Deployed, verified, invariant suite green | L1 |
| Tech | Transparency prototype reading vault and supply | Public URL on testnet | L5 |
| Security | Threat model v1 and key ceremony plan | Reviewed by an external auditor | L7 |
| Compliance | AML/CFT policy draft, risk assessment, provider shortlist | Reviewed by counsel | L4 |
| Brand | Name, trademark, domain, ticker checks | Cleared or renamed | Overview |

## Build order

1. Scaffold the monorepo exactly as the Build Playbook describes; set up Foundry, pnpm, Turborepo, CI.
2. Implement KND token with its full test file before anything else depends on it.
3. Implement ParticipantRegistry, then BasketVault, then the handler-based invariant suite for INV-1, INV-2, INV-3, INV-6, INV-7, INV-8.
4. Write deploy scripts with a parameters file per environment; deploy to Base Sepolia with mock USDC and a mock gold token modelled on DGLD (18 decimals, with optional transfer fee, pause and blacklist toggles).
5. Wire roles to test Safes and a TimelockController with a 5-minute delay on testnet.
6. Build the transparency prototype that reads supply, vault balances and basket quantities.
7. Run an internal review against the L1 checklist; book two audit slots for P1.

## Exit gate

- [ ] Issuer jurisdiction chosen and entity incorporated or in progress
- [ ] Written classification opinion covering issuer country, Kenya and Nigeria
- [ ] Two signed partner LOIs with indicative pricing
- [ ] Basket spec v1 and ADR-010 accepted
- [ ] Testnet contracts deployed and verified; invariant suite green at 10,000 runs, depth 100
- [ ] Threat model reviewed; key ceremony plan written
- [ ] Two audit firms booked for P1
- [ ] Name cleared

## Risks in this phase

| Risk | Mitigation |
| --- | --- |
| Counsel says KND is a regulated e-money or asset-referenced token requiring a licence you cannot get quickly | Pick the jurisdiction with the clearest path; consider partnering with a licensed issuer as issuer of record |
| No partner signs | Start with partners you already talk to (for example Pretium in Kenya); offer revenue share on network fees |
| Gold feed not available on Base | Resolved: Chainlink XAU/USD and PAXG/USD are live on Base (ADR-010) |

## Agent task pack

Feed each task to your coding agent with the named spec tab pasted as context. Do them in order.

1. T0.1 Scaffold the repository from Build Playbook section 2; add CI that runs forge fmt check, forge test, pnpm lint, pnpm typecheck.
2. T0.2 Implement contracts/src/token/KandaToken.sol per L1 section 3.1; write test/unit/KandaToken.t.sol covering every function and revert.
3. T0.3 Implement ParticipantRegistry per L1 section 3.2 with tests.
4. T0.4 Implement BasketVault per L1 section 3.3 with unit tests, including a fee-on-transfer mock.
5. T0.5 Implement the invariant handler and invariants per L1 section 5.
6. T0.6 Write script/Deploy.s.sol and config/base-sepolia.json per L1 section 7; deploy and verify.
7. T0.7 Build apps/transparency per L5 section 5 against Base Sepolia.
