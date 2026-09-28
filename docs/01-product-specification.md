# Product Specification

Kanda lets a business in one African country pay a business in another in minutes, at an all-in cost under 1.5%, settling in KND instead of routing through USD correspondent banks. This tab defines who it serves, what it must do in each phase, and how success is measured. Requirement IDs (FR-, NFR-) are referenced from the layer specs.

## 1. Problem

- Sub-Saharan Africa is the most expensive region to send money to, averaging 8.45% per remittance in Q1 2025; some intra-African corridors such as Tanzania to Rwanda cost 15 to 20% ([TechCabal](https://techcabal.com/es/2026/03/31/how-papss-is-meeting-cross-border-promise-four-years-on/)).
- More than 80% of African cross-border payments are estimated to route through correspondent banks in the US or Europe, adding 2 to 5% per transaction in conversions (same source).
- Holders want protection from local-currency depreciation, which is why USDT dominates informally. Local-currency stablecoins do not meet that need: cNGN had 24 holders and about 1.6M USD of supply in August 2026 ([DIA](https://www.diadata.org/map/global-stablecoins/stories/08-cngn-issuance-not-adoption/)).
- Businesses cannot use informal USDT rails openly: no invoices, no compliance trail, counterparty and freeze risk, and unclear legality in some markets.

## 2. Users and jobs

| Persona | Job to be done | Pain today | What Kanda gives |
| --- | --- | --- | --- |
| SME importer (Nairobi) | Pay a supplier in Lagos | Bank wire takes 2 to 5 days, double FX conversion, high fees | One quote in KES, supplier paid in NGN, minutes, invoice-linked receipt |
| SME exporter or supplier (Lagos) | Get paid from Kenya | Delayed receipts, FX haircut, paperwork | Payout to bank account in NGN, or hold KND as a hedge |
| Business treasurer | Hold working capital without local-currency erosion | USDT is informal and off-books | Auditable, compliant KND balance with on-chain proof of reserves |
| Ramp partner (PSP, licensed exchange) | Serve cross-border customers without nostro accounts in every currency | Pre-funding in many currencies ties up capital | One settlement asset (KND) as inventory; earns FX spread |
| Authorized participant (market maker) | Arbitrage KND price vs NAV; provide liquidity | No transparent African settlement asset to make markets in | In-kind create and redeem, on-chain, no oracle risk |
| Developer or fintech integrator | Add cross-border payouts to an app | Fragmented corridor APIs | One Partner API and SDK across corridors |
| Compliance officer (partner or regulator) | See that flows are screened and traceable | Informal rails are opaque | Travel Rule data, screening logs, analytics exports |

## 3. Positioning against alternatives

| Option | Speed | Cost | Holds value vs local currency | Compliant for businesses | Programmable |
| --- | --- | --- | --- | --- | --- |
| Bank wire via correspondent | 2 to 5 days | High | n/a | Yes | No |
| Informal USDT (P2P, Tron) | Minutes | Low to medium | Yes | Weak | Yes |
| Local stablecoins (cNGN, nTZS) | Minutes | Low | No | Yes locally | Yes |
| PAPSS | Near real time | Lower than wires | n/a | Yes | Bank-only |
| Kanda | Minutes | Target under 1.5% all-in | Yes | Yes | Yes |

Kanda's edge over USDT is licensed ramps on both sides, business-grade compliance and receipts, and fully verifiable reserves. Its edge over local stables is that holders keep value.

## 4. Scope by phase

| Phase | In scope | Explicitly out of scope |
| --- | --- | --- |
| P0 Foundations | Entity, counsel, jurisdiction, basket parameters, partner LOIs, testnet token and vault, threat model | Mainnet, real users |
| P1 Corridor MVP | KND on Base, BasketVault, payment escrow, Partner API, business web app, transparency page, Kenya to Nigeria corridor, supply cap | Retail app, DEX incentives, other chains, off-chain reserves |
| P2 Multi-corridor and FX hub | Ghana, Uganda, Tanzania, South Africa corridors; Uniswap v4 hub pools with cNGN, nTZS, cKES; RFQ settlement; FX oracle hub; CCIP to Celo and Avalanche; off-chain T-bill reserves with attestation; mobile app with passkey accounts | Consortium governance |
| P3 Scale and federation | Consortium governance, PAPSS connection, African gold custody, basket reconstitution process, ISO 20022 messaging, institutional APIs | Issuing local-currency stables |

## 5. The KND unit

One KND is a claim on a fixed quantity basket, not a fixed USD value.

```latex
\mathrm{NAV}_{USD}(t) = 0.70 + G \cdot P_{XAU}(t), \qquad G = \frac{0.30}{P_{XAU}(t_0)}
```

- USD leg: 0.70 USD per KND, held as USDC in Phase 1 (0.70e6 base units at 6 decimals).
- Gold leg: G troy ounces per KND, held as DGLD in Phase 1 (ADR-010): allocated, Swiss-vaulted PAMP gold issued by Gold Token SA (MKS PAMP group), 18 decimals, 1 DGLD = 1 fine troy ounce (confirm in the issuer's terms before genesis). Example only: at a genesis gold price of 4,000 USD per ounce, G = 0.000075 oz.
- KND has 18 decimals. Basket quantities are immutable per basket version; a new version is a governance event.
- Gold weight drifts with the gold price. If gold's share of NAV stays outside 20% to 40% for 30 consecutive days, governance must table a reconstitution proposal. Reconstitution sets new quantities so NAV is unchanged at the switch block.
- Display: apps show KND balances in the user's local currency first, using the partner quote, with NAV in USD as secondary.

## 6. Functional requirements

| ID | Requirement | Phase | Priority |
| --- | --- | --- | --- |
| FR-TKN-01 | KND is an ERC-20 with EIP-2612 permit and EIP-3009 transferWithAuthorization | P1 | Must |
| FR-TKN-02 | Only registered minter contracts can mint or burn | P1 | Must |
| FR-TKN-03 | Compliance role can block and unblock addresses; blocked addresses cannot send or receive | P1 | Must |
| FR-TKN-04 | Guardian can pause all transfers; unpause needs admin multisig | P1 | Must |
| FR-PRM-01 | Allowlisted participants create KND by depositing the exact basket in kind | P1 | Must |
| FR-PRM-02 | Allowlisted participants redeem KND for the exact basket in kind | P1 | Must |
| FR-PRM-03 | Per-participant daily create and redeem limits, global supply cap | P1 | Must |
| FR-PRM-04 | Zap periphery: create KND from USDC only, swapping the gold leg with a slippage bound | P1 | Should |
| FR-PRM-05 | Cash create and redeem through the issuer desk against off-chain reserves | P2 | Should |
| FR-PAY-01 | Partner creates a payment intent with a locked quote, sender and recipient details, and a Travel Rule payload | P1 | Must |
| FR-PAY-02 | Sending partner locks KND in escrow against the intent id | P1 | Must |
| FR-PAY-03 | Receiving partner confirms fiat payout; escrow releases KND to the receiving partner | P1 | Must |
| FR-PAY-04 | Unconfirmed intents expire and refund to the sender partner after a timeout | P1 | Must |
| FR-PAY-05 | Disputes freeze an intent until the arbiter role resolves it | P1 | Should |
| FR-PAY-06 | Batch settlement of many intents in one transaction | P2 | Could |
| FR-QTE-01 | All-in quote: send amount, receive amount, fees, FX rates, expiry, shown before confirmation | P1 | Must |
| FR-QTE-02 | Quote rejected if any partner rate deviates from the reference beyond the corridor threshold | P1 | Must |
| FR-WAL-01 | Business accounts with multi-user roles (maker, approver, viewer) | P1 | Must |
| FR-WAL-02 | Self-custody option: connect a wallet (RainbowKit) to hold and send KND | P1 | Should |
| FR-WAL-03 | Passkey smart accounts (ERC-4337) for non-crypto users | P2 | Must |
| FR-PTN-01 | Partner portal: inventory, intents to pay out, settlements, statements | P1 | Must |
| FR-PTN-02 | Partner API with sandbox, webhooks, idempotency | P1 | Must |
| FR-TRN-01 | Public transparency page: supply per chain, vault balances, NAV, basket version, collateral ratio | P1 | Must |
| FR-TRN-02 | Monthly independent attestation published once off-chain reserves exist | P2 | Must |
| FR-CMP-01 | Screen every counterparty wallet and every participant at onboarding and per transaction | P1 | Must |
| FR-CMP-02 | Travel Rule data exchange between sending and receiving partners | P1 | Must |
| FR-CMP-03 | Case management for alerts with audit trail | P1 | Must |
| FR-OPS-01 | Admin console: roles, limits, corridor switches, pause, reconciliation view | P1 | Must |
| FR-OPS-02 | Daily three-way reconciliation: chain, ledger, partner statements | P1 | Must |
| FR-FX-01 | Hub pools KND against USDC and local stables with oracle price bands | P2 | Must |
| FR-FX-02 | On-chain RFQ settlement of signed market-maker quotes | P2 | Should |
| FR-XCH-01 | Burn-and-mint cross-chain transfers with per-lane rate limits | P2 | Must |

## 7. Non-functional requirements

| ID | Requirement | Target |
| --- | --- | --- |
| NFR-01 | Partner API availability | 99.9% monthly |
| NFR-02 | Quote latency | p95 under 800 ms |
| NFR-03 | On-chain leg of a payment | p95 under 60 s from lock to release on Base |
| NFR-04 | End-to-end payment, fiat legs included | p95 under 30 min (partner-dependent) |
| NFR-05 | Reconciliation | Zero unexplained breaks at daily close |
| NFR-06 | Collateralization | Vault assets at or above 100% of basket times supply, every block |
| NFR-07 | Audit logs | Append-only, retained at least 7 years |
| NFR-08 | Personal data | Stored off-chain only; residency per partner country law |
| NFR-09 | Key security | No single key can mint, upgrade or move reserves |
| NFR-10 | Recovery | RPO 5 min, RTO 1 hour for off-chain services |

## 8. Key user journeys

1. Kenya to Nigeria payment
   1. Importer logs in, enters supplier and amount in NGN or KES, attaches invoice.
   2. Kanda returns an all-in quote locked for 10 minutes; an approver confirms.
   3. Importer pays KES to the Kenyan partner by M-Pesa or bank transfer.
   4. Kenyan partner locks KND in escrow; Nigerian partner sees the intent.
   5. Nigerian partner pays NGN to the supplier's bank and confirms; escrow releases KND to it.
   6. Both businesses get receipts with the intent id, rates and the on-chain transaction hash.
2. Holding KND: a business keeps part of a payout as KND and redeems later through a partner.
3. Partner rebalancing: the Nigerian partner accumulates KND and redeems it in kind, or sells to the Kenyan partner OTC, or trades on a DEX.
4. Authorized participant arbitrage: when KND trades above NAV, the participant creates in kind and sells; below NAV, buys and redeems.
5. Compliance hold: a screening hit moves the intent to hold, the escrow does not release, an analyst resolves the case.

## 9. Pricing and revenue (placeholders to validate in P0)

| Line | Who pays | Placeholder |
| --- | --- | --- |
| In-kind create or redeem fee | Participants | 5 to 10 bps |
| Corridor network fee | Sending partner, passed to customer | 20 to 40 bps of payment value |
| Partner FX spread | Customer, kept by partner | Partner-set, capped by corridor policy |
| API platform fee | Integrators | Tiered monthly |
| Reserve yield | Issuer | P2 onward, from T-bill sleeve |

## 10. Success metrics

| Metric | P1 target (placeholder) |
| --- | --- |
| Monthly corridor volume | 1M USD by month 6 of pilot |
| All-in customer cost | Under 1.5% |
| Active paying businesses | 50 |
| Secondary price vs NAV | Within 25 bps, 95% of hours |
| Reconciliation breaks | Zero unresolved over 30 days |
| Collateral ratio | 100% or higher, every block |

## 11. Regulatory and legal requirements

- Issuer jurisdiction is open. Candidates to assess with counsel: Kenya (VASP regime), Mauritius, Rwanda (Kigali IFC), South Africa (CASP licensing), and the UAE as an offshore option. Decide in P0.
- Obtain a legal opinion on KND's classification (payment token, e-money, commodity-referenced or asset-referenced token) in the issuer jurisdiction and in each corridor country.
- Every ramp partner must hold the licences its country requires for fiat on and off ramps and virtual assets; Kanda does not touch fiat in Phase 1.
- Capital controls: each corridor needs a written view on whether customers holding KND counts as holding foreign-currency assets. Some regulators will treat a hard-asset stable as a capital flight channel; per-country holding limits may be required.
- Travel Rule compliance between partners from day one.
- Data protection: Kenya Data Protection Act 2019, Nigeria Data Protection Act 2023 and equivalents; personal data never on-chain.
- The founder does not have in-house regulatory expertise; budget for external counsel and a compliance officer in P0.

## 12. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Regulator treats KND as capital flight | Corridor shut | Partner-led licensing, holding limits, B2B trade focus, early regulator engagement |
| Gold drawdown lowers KND in USD terms | User losses, trust | Clear disclosure, 30% cap, local-currency display, reconstitution rules |
| USDC or DGLD issuer failure, freeze or seizure | Reserve impairment | Diversify in P2 (T-bills, second gold token), monitoring, concentration limits |
| Smart contract bug | Loss of reserves | Two audits, invariant fuzzing, caps, pause, bug bounty |
| Key compromise | Unauthorized mint or upgrade | Multisig, timelock, role separation, HSM or MPC for operational keys |
| Partner fails to pay out | Customer loss | Escrow only releases on confirmation, partner collateral, SLA and offboarding |
| Low adoption (the cNGN pattern) | No business | Start from real B2B trade flows and partner distribution, not token listings |
| Secondary depeg vs NAV | Price confusion | In-kind arbitrage, participant incentives, pool oracle bands |
| Oracle manipulation | Bad quotes | No oracle in core mint path; medians, staleness checks, divergence holds |

## 13. Open decisions

- [ ] Issuer jurisdiction and entity structure
- [ ] Final basket split (70/30 proposed) and genesis date
- [x] Gold instrument for Phase 1: DGLD on Base (ADR-010, decided 27 Sep 2026)
- [ ] Kenyan and Nigerian ramp partners (candidates: Pretium in Kenya; Yellow Card and Busha operate in Nigeria)
- [x] Gold feeds on Base: Chainlink XAU/USD primary, Chainlink PAXG/USD secondary (ADR-010)
- [ ] Name, trademark and ticker clearance
- [ ] Audit firms (two) and bug bounty platform

## Sources

- [TechCabal: PAPSS four years on](https://techcabal.com/es/2026/03/31/how-papss-is-meeting-cross-border-promise-four-years-on/)
- [DIA: cNGN issuance, not adoption](https://www.diadata.org/map/global-stablecoins/stories/08-cngn-issuance-not-adoption/)
- [Ahram Online: PAPSS and Instapay](https://english.ahram.org.eg/News/576342.aspx)
