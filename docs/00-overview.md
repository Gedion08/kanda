# Kanda — Product & Architecture Specification

Sep 27, 2026 · @Gideon

## What Kanda is

Kanda is a reserve-backed settlement unit, KND, plus a network of licensed ramp partners that moves money between African currencies without a US correspondent-bank detour. Phase 1 ships one corridor, Kenya to Nigeria, on Base, for small and medium businesses.

Kanda is Swahili for region or zone. It is a working name: trademark, domain and ticker checks are a Phase 0 task.

One KND is a fixed basket: 0.70 US dollars plus G troy ounces of gold, where G is set once at genesis so that gold is 30% of the value on day one. KND is not pegged to 1 USD. Its USD value moves with the gold price at roughly 30% weight, and it holds value against every African currency the way USD stables do.

### Core design decisions

| # | Decision | Choice | Why | Revisit |
| --- | --- | --- | --- | --- |
| D1 | Unit of value | 1 KND = 0.70 USD + G oz gold, fixed quantities | No African government controls it; protects holders from local-currency depreciation; gold gives a non-dollar component | Phase 3 reconstitution |
| D2 | Reserves in Phase 1 | 100% on-chain in a BasketVault holding USDC and PAXG | Anyone can verify backing from chain state; no bank custody needed for the MVP | Phase 2 adds T-bills and allocated gold off-chain, with attestation |
| D3 | Primary market | In-kind create and redeem by allowlisted participants; no price oracle in the mint or burn path | Removes oracle manipulation from the most dangerous code path | Phase 2 adds cash create via issuer desk |
| D4 | Secondary market | Freely transferable ERC-20 with a blocklist, not an allowlist | Tradability, DEX pools, wallet-to-wallet payments | Stays |
| D5 | Local FX rates | Quoted by licensed local ramp partners; Kanda's FX oracle is reference-only and triggers holds on divergence | Kanda never has to choose between an official and a parallel rate | Phase 2 on-chain pools use oracle bands |
| D6 | Local stablecoins | Integrate cNGN, nTZS, cKES and others; never issue them | Local issuers carry local licensing | Stays |
| D7 | Chain | Base first; Celo and Avalanche in Phase 2 via Chainlink CCIP | cNGN and nTZS already live on Base; low fees | Phase 2 |
| D8 | Settlement model | Partners pre-fund KND inventory; payments settle through an on-chain escrow keyed by payment intent | Replaces nostro pre-funding in every currency with one asset | Phase 2 adds RFQ settlement |
| D9 | Governance | Safe multisigs, 48-hour timelock, pause-only guardian | Fast incident response, slow and visible upgrades | Phase 3 consortium of banks and PSPs |
| D10 | First market | Kenya to Nigeria, B2B, capped supply | Real trade flow, KYB-able users, two strong ramp ecosystems | Phase 2 adds Ghana, Uganda, Tanzania, South Africa |

### What KND deliberately is not

- Not a local-currency stablecoin. Those exist and have weak holder demand; Kanda routes between them.
- Not a 1 USD stablecoin. Merchants see local-currency prices; the app shows KND value in KES, NGN and USD.
- Not a replacement for PAPSS. PAPSS is a bank-to-bank rail; Kanda is an open, programmable settlement asset that can connect to it in Phase 3.

## Document map

Read the first three in order, then work phase by phase: each phase tab lists which layer specs its tasks use.

| Tab | What it holds | Use it when |
| --- | --- | --- |
| 01 Product Specification | Problem, users, positioning, the KND unit, functional and non-functional requirements, pricing, metrics, legal, risks, open decisions | Deciding what to build and why |
| 02 Architecture Design | System diagram, components, role map, invariants, money flows, data, oracles, security, environments, stack, ADRs, failure modes | Any design question; it overrides layer specs |
| 03 Phases | Phase summary and gates | Planning |
| P0 Foundations | Legal path, partners, testnet vault | Now |
| P1 Corridor MVP | Kenya and Nigeria corridor on Base mainnet | After the P0 gate |
| P2 Multi-corridor and FX hub | Five corridors, FX hub, CCIP, off-chain reserves, mobile | After the P1 gate |
| P3 Scale and federation | Consortium governance, PAPSS, African gold custody | After the P2 gate |
| 04 Layer specs | Index of the seven layer specs | Finding a spec |
| L1 Smart contracts | Contract interfaces, rules, parameters, invariants, tests, deployment | Writing Solidity |
| L2 Oracles and pricing | NAV, FX reference, quote algorithm, hold policy | Pricing and quotes |
| L3 Backend and ledger | Modules, schema, state machine, indexer, ledger, reconciliation, webhooks | Backend work |
| L4 Compliance and risk | Responsibilities, onboarding, screening, Travel Rule, monitoring, cases, data protection | Compliance work |
| L5 Client apps | Business app, partner portal, admin console, transparency page, mobile | Front-end work |
| L6 Partner API and SDK | Endpoints, auth, examples, SDK, sandbox, ISO 20022 | Partner integration |
| L7 Infra, security and ops | Hosting, keys, CI/CD, alerts, runbooks, upgrades | Infra, security and launch |
| 05 Build Playbook | Repo layout, AGENTS.md, prompt templates, definition of done | Every coding session |

## Phase overview

&#91;embedded content: Kanda roadmap · 4 phases, 3 gates\]

Each diamond is a gate: its criteria sit under it, and the full checklists are in 03 Phases. P0 and P1 touch every layer; P2 adds FX hub, cross-chain and reserve work to L1 to L3; P3 is mostly governance, L6 messaging and custody.

## Using these docs while vibecoding

The docs are the spec; the code follows them, never the other way round. The full routine, the AGENTS.md rules file and the prompt templates are in 05 Build Playbook.

- Source of truth, in order: 02 Architecture Design, then the layer spec, then the phase tab, then the agent's judgement.
- Export each tab as markdown into docs/ in the repo so agents read the current version; re-export when a tab changes.
- Work one task at a time from the phase task packs, starting with P0 task T0.1.
- Give the agent three things per task: AGENTS.md, the named layer spec, the prompt template. Ask for tests from the spec tables first.
- When the agent hits a gap, stop and fix the spec here first. Comment on any passage and I can revise it.

## Glossary

| Term | Meaning in these docs |
| --- | --- |
| KND | Kanda's token: one unit of the fixed basket, 18 decimals |
| NAV | Net asset value of one KND in USD: 0.70 plus G times the gold price |
| Basket leg | One reserve asset in the basket (USD leg, gold leg) with a fixed quantity per KND |
| G | Troy ounces of gold per KND, fixed at genesis so gold is 30% of NAV on day one |
| Basket version | A set of leg quantities; changes only through reconstitution |
| Reconstitution | Governance process that sets new leg quantities while keeping NAV unchanged at the switch block |
| In-kind create and redeem | Minting KND by depositing the exact basket assets, or burning KND to receive them; no price oracle involved |
| Authorized participant | Allowlisted firm (usually a market maker) that may create and redeem in kind |
| Ramp partner | Licensed company that converts local fiat to and from KND in its country |
| Corridor | A country pair served by one sending and one receiving partner, for example KE-NG |
| Payment intent | One cross-border payment tracked from quote to completion, with an off-chain id and an on-chain id |
| Escrow | PaymentEscrow contract holding KND for an intent until release, refund or dispute resolution |
| Rate basis | Whether a partner priced its local currency at the official or the market rate |
| Parallel regime | State of a currency whose official and market rates differ beyond the corridor threshold |
| Divergence hold | A quote paused for review because a partner rate is too far from the reference |
| Coverage ratio | Reserve held for a leg divided by the reserve required for current supply; must stay at or above 100% |
| PoR | Proof of reserves: on-chain vault balances in P1, plus attested off-chain holdings from P2 |
| Travel Rule | Obligation to pass originator and beneficiary data between service providers with a transfer |
| IVMS101 | Standard data model for Travel Rule messages |
| CCIP | Chainlink's cross-chain protocol used to move KND between Base, Celo and Avalanche |
| Timelock | Contract that delays admin actions by 48 hours so they are public before they execute |
| Guardian | Safe that can pause the system but cannot change or unpause it |
| Hub pool | On-chain liquidity pool pairing KND with USDC or a local stablecoin |
| RFQ | Request for quote: market makers sign prices that are settled on-chain |
| Finality depth | How long the backend waits after a chain event before acting on it |
