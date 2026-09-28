# P0 exit gate tracker

28 Sep 2026 · Source: P0 Foundations (exit gate and workstreams), PSD sections 11 and 13, L7 section 2 · Owner: founder

P0 closes only when every row below is done. The code rows move with the task pack. The other rows need people outside the repo: counsel, partners, auditors and a trademark agent. This file records their status and evidence so the gate can be signed off.

**Don't commit confidential documents.** Legal opinions, signed LOIs and audit engagement letters stay in the company's document store, not in git. Record here only the date, the counterparty, and where the document is kept.

## Status

"Not recorded" means nobody has written a status here yet. It doesn't mean the work hasn't started. Update each row when it moves.

| # | Exit gate item | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Issuer jurisdiction chosen; entity incorporated or in progress | Not recorded | |
| 2 | Written classification opinion: issuer country, Kenya, Nigeria | Not recorded | |
| 3 | Two signed partner LOIs with indicative pricing (one Kenyan, one Nigerian ramp) | Not recorded | |
| 4 | Basket spec v1 and ADR-010 accepted | Partly done: ADR-010 accepted 27 Sep 2026. Open: confirm 1 DGLD = 1 troy oz in the issuer's terms (G-02); G is fixed at genesis | Review doc section 8 |
| 5 | Testnet contracts deployed and verified; invariant suite green at 10,000 runs, depth 100 | In progress: T0.2 KandaToken and T0.3 ParticipantRegistry built and tested (slither pending). T0.4 to T0.7 to do | This repo |
| 6 | Threat model reviewed; key ceremony plan written | Not started. The key ceremony outline is in L7 section 2; the external auditor review is still to come | |
| 7 | Two audit firms booked for P1 | Not recorded | |
| 8 | Name cleared ("Kanda", "KND") | Not started | See section 3 |

## 1. What each non-code item needs

### Classification opinion (row 2)

- Ask counsel in the issuer jurisdiction, Kenya and Nigeria whether KND is a payment token, e-money, a commodity-referenced token or an asset-referenced token, and what licence each answer implies (PSD section 11).
- Give counsel the Overview's "What KND deliberately is not", the basket definition (0.70 USD + G oz gold), the in-kind create and redeem model, and the blocklist and pause powers.
- Also ask about holding limits (the capital-controls point in PSD section 11).
- Ask counsel to review the public token texts (`docs/brand/token-profile.md`) against the opinion. The brand release in section 4 depends on this review.
- **Done when** a written opinion covers all three jurisdictions.

### Partner LOIs (row 3)

- One Kenyan and one Nigerian licensed ramp, each with indicative pricing. P0's risk table names partners you already talk to, such as Pretium in Kenya.
- The LOI should state the corridor, the expected monthly volume band, the indicative FX spread and fees, the pre-funding model in KND, and the compliance duties (Travel Rule, screening) from L4.
- **Done when** both are signed.

### Threat model and key ceremony plan (row 6)

- Threat model v1 covers the contracts (L1 section 8 checklist), roles and keys (ADD section 4, L7 section 2), the oracles (L2), the backend and ledger (L3), and the partner API (L6). Use one table per trust boundary: asset, threat, control, residual risk.
- The key ceremony plan expands the outline in L7 section 2 into a script:
  - who is present and which Safe each person signs for
  - how each signer is verified (in person or by video)
  - a testnet transaction for each signer
  - recording the addresses in `config/base.json`
  - a fresh deployer key, then WireRoles and VerifyRoles
  - publishing the role report
- **Done when** an external auditor has reviewed both.
- These two are engineering documents, so I can draft them in the repo when you ask.

### Audit firms (row 7)

- Book two firms for P1. Share the contract list and size, the L1 section 8 checklist, and the target window after T1.x code freeze.
- Choose a bug bounty platform at the same time (PSD open decision).
- **Done when** both slots are confirmed in writing.

## 2. Contract rows still to do

- T0.4 BasketVault
- T0.5 invariant suite (INV-1, 2, 3, 6, 7, 8)
- T0.6 deploy and verify on Base Sepolia, and wire roles to test Safes with a 5-minute timelock
- T0.7 transparency page
- Slither on every contract. The owner runs it in the VS Code extension. Still to check: KandaToken, ParticipantRegistry.

## 3. Name clearance ("Kanda" and "KND")

Do all of these before the brand goes public. A trademark agent or counsel should do or confirm the trademark searches.

- [ ] **Trademark searches** in the issuer jurisdiction, Kenya (KIPI), Nigeria (Trademarks, Patents and Designs Registry) and the WIPO Global Brand Database, in Nice classes 9 (software), 36 (financial services) and 42 (software services). Add any market named in P2 before expanding there.
- [ ] **Ticker check:** search for existing tokens with the symbol `KND` on CoinGecko, CoinMarketCap, Basescan and the major token lists. A collision doesn't block by itself, but it affects wallet display and exchange listings.
- [ ] **Language check:** confirm "Kanda" has no negative or confusing meaning in the corridor languages: Swahili, Hausa, Yoruba, Igbo, Pidgin, and French for P2.
- [ ] **Domain and handles:** choose and register the primary domain and the social handles. These also fill the empty website and support fields in the token profile.
- [ ] **Decision recorded:** either "Kanda and KND cleared" with the date and the counsel reference, or a rename. A rename changes the on-chain name and symbol in `KandaToken` before any deployment that matters, the EIP-712 domain name, and every brand file.

## 4. Brand release gate

The logo files, brand system and token profile are **internal** today. Only design reviews, counsel, partners under NDA and auditors may see them.

They move to **public** when all of these are true:

1. Row 8 (name clearance) is done and recorded above.
2. Counsel has reviewed the token texts against the classification opinion (row 2), or confirmed in writing that the review can wait.
3. For the token-list entry only: the token is deployed on the network being listed, and `knd-256.png` has a permanent public URL.

When they are:

1. Change the status line from "Internal" to "Public" in `docs/brand/README.md`, `docs/brand/token-profile.md` and the brand system (https://claude.ai/artifact/AyDi16xpft6YtNu32Rr5L5, README and Token profile). Add the date and this file as the reason.
2. Fill in the website and support email in the token profile.
3. Fill in `docs/brand/kanda.tokenlist.template.json` as its instructions say. Validate it, then publish it.
4. Submit the token info to Basescan with the short description and `knd-256.png`.
5. Share the brand system from its Share menu with whoever needs it.
