# P3 Scale and federation

P3 hands Kanda's governance to a consortium of African banks and PSPs, connects fiat legs to PAPSS, and moves gold custody onto the continent. Exit when governance runs through member institutions and at least one fiat leg settles through PAPSS.

## Scope

| In | Out |
| --- | --- |
| Consortium charter, member onboarding, on-chain governor | Issuing local-currency stables |
| Reserve committee and published reserve policy |  |
| PAPSS connectivity for partner fiat legs through a member bank |  |
| ISO 20022 message mapping for payment intents |  |
| African gold custody for the gold sleeve |  |
| Basket reconstitution process run end to end |  |
| Study of additional basket components (EUR, CNY) |  |
| Institutional products: bulk payouts, treasury accounts, trade-finance hooks for AfCFTA trade |  |

## Governance model

| Body | Members | Decides | On-chain form |
| --- | --- | --- | --- |
| Consortium assembly | Member banks and PSPs, one seat each, weighted by stake rules in the charter | Basket version, fees, new corridors, upgrades | OZ Governor with member NFT seats, feeding the timelock |
| Reserve committee | Treasury experts appointed by the assembly | Custodians, reserve composition within policy, attestor | Safe with committee members |
| Risk and compliance committee | Compliance heads of members | Corridor policies, limits, blocklist policy | Safe holding COMPLIANCE\_ROLE |
| Guardian | Security council | Emergency pause only | Safe holding PAUSER\_ROLE |

The founding issuer keeps operational roles under service agreements; admin authority moves to the governor and timelock.

## PAPSS and gold

- PAPSS runs across 30 African countries with more than 200 banks, PSPs and fintechs connected ([Ahram Online](https://english.ahram.org.eg/News/576342.aspx)). Kanda joins through a member bank so that partner fiat legs can settle through PAPSS where both sides are connected, cutting the fiat side of each corridor.
- Afreximbank reports that technical studies for a proposed African Gold Bank are nearing completion, with the aim of letting African central banks store gold ([Business Today Egypt](https://www.businesstodayegypt.com/amp/1/7467/Egypt-set-to-benefit-from-expanded-financing-PAPSS-rollout-in)). If it launches, it is the first candidate custodian for the gold sleeve; otherwise use an LBMA-standard vault on the continent with independent bar audits.

## Reconstitution procedure

1. Trigger: gold weight outside 20% to 40% for 30 days, or a governance proposal.
2. Reserve committee proposes new quantities that keep NAV unchanged at a named block.
3. Assembly votes; timelock queues a new basket version.
4. Treasury rebalances reserves with participants before the switch block.
5. Vault switches basket version atomically; in-kind create and redeem use the new quantities from that block.

## Exit gate

- [ ] Charter signed by at least five member institutions in three countries
- [ ] Admin roles transferred to governor and timelock
- [ ] One corridor's fiat legs settling through PAPSS
- [ ] Gold sleeve custody on the continent with a published bar list
- [ ] One reconstitution rehearsal completed on testnet

## Agent task pack

1. T3.1 Implement KandaGovernor (OZ Governor, member-seat voting) and migration script moving admin roles.
2. T3.2 Implement basket versioning and switch logic in BasketVault per L1 section 3.3.
3. T3.3 Map payment intents to ISO 20022 pacs.008 and pacs.002 per L6 section 6.
4. T3.4 Build member onboarding and seat issuance in the admin console per L5.

## Sources

- [Ahram Online: PAPSS and Instapay](https://english.ahram.org.eg/News/576342.aspx)
- [Business Today Egypt: Afreximbank on PAPSS and African Gold Bank](https://www.businesstodayegypt.com/amp/1/7467/Egypt-set-to-benefit-from-expanded-financing-PAPSS-rollout-in)
