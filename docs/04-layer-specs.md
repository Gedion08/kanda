# Layer specs

Each sub-tab specifies one layer so a coding agent can build it without guessing: stack, folder layout, interfaces, data models, state machines, acceptance tests and an ordered task list. When a layer spec and the Architecture Design disagree, the Architecture Design wins and the layer spec gets fixed.

| Layer | Covers | First needed |
| --- | --- | --- |
| L1 Smart contracts | Token, vault, registry, escrow, oracles, hooks, RFQ, CCIP, cash desk | P0 |
| L2 Oracles and pricing | NAV, FX reference, quotes, divergence policy | P1 |
| L3 Backend and ledger | Gateway, orchestrator, ledger, treasury, indexer, reconciliation | P1 |
| L4 Compliance and risk | KYB, screening, Travel Rule, cases, monitoring, reporting | P1 |
| L5 Client apps | Business app, partner portal, admin console, transparency page, mobile | P0 (transparency), P1 |
| L6 Partner API and SDK | REST, webhooks, SDK, sandbox, RFQ, ISO 20022 | P1 |
| L7 Infra, security and ops | Environments, keys, CI/CD, monitoring, incidents, audits | P0 |
