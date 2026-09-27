# P2 Multi-corridor and FX hub

P2 turns one corridor into a network: five countries, an on-chain FX hub where KND is the vehicle asset between local stablecoins, KND on three chains, and yield-bearing off-chain reserves. Exit when at least four corridors are live, hub pools hold price within bands, and the first monthly reserve attestation is published.

## Scope

| In | Out |
| --- | --- |
| Corridors: Ghana, Uganda, Tanzania, South Africa added | Consortium governance |
| Uniswap v4 hub pools: KND/USDC, KND/cNGN, KND/nTZS, KND/cKES | PAPSS integration |
| OracleBandHook, optional AllowlistHook | Physical gold custody in Africa |
| FXReferenceOracle on-chain |  |
| RFQSettler for signed market-maker quotes |  |
| CCIP burn-and-mint to Celo and Avalanche |  |
| Off-chain T-bill sleeve, CashDesk, monthly attestation, proof-of-reserve gated minting |  |
| Mobile app with passkey smart accounts |  |
| Second gold token for diversification |  |
| Batch settlement in PaymentEscrow |  |

## Why a hub

With N local currencies, direct pools need N times (N minus 1) divided by 2 pairs; with KND as the hub they need N. Ten currencies means 45 thin pools versus 10 deep ones. Routing KES to NGN becomes cKES to KND to cNGN in one transaction.

## Workstreams and deliverables

| Workstream | Deliverable | Done when | Spec |
| --- | --- | --- | --- |
| Corridors | Partner per new country, corridor policy, limits | Each corridor passes sandbox and pilot | L6, L4 |
| FX hub | Hub pools and OracleBandHook | Price inside band 99% of blocks in staging simulation | L1, L2 |
| FX hub | Liquidity program with authorized participants and partners | Target depth per pool met (set per pool) | L3 |
| Oracles | FXReferenceOracle with signed partner rates and official rates | Divergence flags visible on-chain | L2 |
| RFQ | RFQSettler and market-maker quote API | Two market makers quoting | L1, L6 |
| Cross-chain | CCIP token pools on Celo and Avalanche with rate limits | Supply per chain reconciles to vault | L1, L3 |
| Reserves | Custodian for T-bills, CashDesk contract, attestor engaged, PoR feed | First attestation published; minting gated by PoR | L1, L3, L7 |
| Mobile | Expo app with ERC-4337 passkey accounts and recovery | App store release in two countries | L5 |
| Integrations | Optional: list KND as a savings asset in Asili Pay | Integration live after liquidity and oracle maturity | L6 |
| Ops | Temporal decision for workflows | ADR-008 closed | L3 |

## Reserve model change

From P2 the backing is split: the on-chain BasketVault keeps a liquidity sleeve for in-kind flows, and the rest sits off-chain in T-bills and allocated gold with a custodian. Full backing becomes vault assets plus attested off-chain assets, per basket leg, at least equal to supply times basket quantities. CashDesk mints only when a proof-of-reserve feed shows headroom, and the transparency page shows both sleeves separately.

## Local stablecoins to integrate (confirm current status before build)

| Currency | Candidate token | Chain |
| --- | --- | --- |
| NGN | cNGN | Base and others |
| TZS | nTZS | Base |
| KES | cKES (Mento) | Celo |
| XOF | eXOF (Mento) | Celo |
| ZAR, GHS, UGX | Survey in P2 start | Various |

Only integrate tokens that publish reserve attestations; set pool caps lower for tokens without them.

## Exit gate

- [ ] At least four corridors live with pilot volume
- [ ] Hub pools within oracle band 99% of blocks over 30 days
- [ ] RFQ settlement live with two market makers
- [ ] Cross-chain supply reconciles to vault every day for 30 days
- [ ] First monthly attestation published; PoR-gated minting live
- [ ] Mobile app live in two countries
- [ ] Third audit covering all P2 contracts complete

## Agent task pack

1. T2.1 Implement OracleBandHook per L1 section 3.7 with tests on a local v4 PoolManager.
2. T2.2 Implement FXReferenceOracle per L2 section 3.
3. T2.3 Implement RFQSettler per L1 section 3.8 with EIP-712 signature tests.
4. T2.4 Configure CCIP token pools per L1 section 3.9 and write the cross-chain supply reconciliation job per L3 section 8.
5. T2.5 Implement CashDesk with PoR gating per L1 section 3.10; update INV-1 to include attested reserves.
6. T2.6 Add batch release and refund to PaymentEscrow per L1 section 3.4.
7. T2.7 Build the Expo mobile app per L5 section 6.
8. T2.8 Build the market-maker RFQ endpoints per L6 section 5.
