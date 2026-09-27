# Build Playbook

This tab is what you paste into your coding agent. It fixes the repository shape, gives the agent a standing rules file, and provides prompt templates that point at the right spec section, so every task is built from the docs rather than from the agent's guesses.

## 1. How to work

1. One task at a time, in the order of the phase task packs (P0 T0.1 first).
2. For each task, give the agent: the AGENTS.md file below, the named layer spec tab exported as markdown, and the task prompt from section 4.
3. The agent writes tests first from the spec's tables (transitions, invariants, error codes), then the code.
4. You review the diff against the spec, not against the agent's summary.
5. If the spec is wrong or silent, stop and change the spec first (section 6), then continue.

## 2. Repository layout

```
kanda/
  AGENTS.md                 standing rules for coding agents (section 3)
  docs/                     these tabs exported as markdown, one file per tab
  api/openapi.yaml
  contracts/                Foundry project (L1)
  apps/
    api/                    Hono server and workers (L3)
    indexer/                Ponder (L3)
    business/ partner/ admin/ transparency/   (L5)
    mobile/                 P2
  packages/
    db/ chain/ pricing/ shared/ ui/ api-client/ sdk/
  infra/                    Terraform (L7)
  .github/workflows/
  pnpm-workspace.yaml  turbo.json  package.json  .env.example
```

foundry.toml:

```toml
[profile.default]
src = 'src'
test = 'test'
script = 'script'
solc_version = '0.8.28'
evm_version = 'cancun'
optimizer = true
optimizer_runs = 10000

[fuzz]
runs = 10000

[invariant]
runs = 256
depth = 100
fail_on_revert = false

[profile.ci.invariant]
runs = 10000
```

.env.example (names only, never values):

```
DATABASE_URL=
REDIS_URL=
CHAIN_ID=
RPC_URL_PRIMARY=
RPC_URL_SECONDARY=
SIGNER_MODE=local        # local | mpc
MPC_API_KEY=
KMS_PII_KEY_ID=
OIDC_ISSUER=
OIDC_CLIENT_ID=
SCREENING_API_KEY=
WALLET_RISK_API_KEY=
TRAVEL_RULE_API_KEY=
VABAS_EXPORT_URL=
SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=
```

## 3. AGENTS.md (paste at repo root)

```markdown
# Kanda: rules for coding agents

## What this is
Kanda: KND, a reserve-backed basket token (1 KND = 0.70 USD + G oz gold) on Base,
plus a partner network settling cross-border payments through an on-chain escrow.
Specs live in docs/. The Architecture Design (docs/02-architecture-design.md) wins
over any layer spec; a layer spec wins over your assumptions.

## Never
- Never add a contract function, API endpoint, table or state not in the spec.
  Propose a spec change instead.
- Never let any path mint KND without the vault receiving basket assets.
- Never read a price oracle inside BasketVault.
- Never use floats for money. Off-chain: bigint base units and decimal strings.
  Postgres: numeric(78,0).
- Never put personal data on-chain, in logs, or in error messages.
- Never update or delete ledger_entries or intent_events rows.
- Never commit secrets or .env files.
- Never use revert strings, tx.origin, or floating pragmas.

## Always
- Tests first, from the spec tables (transitions, invariants, error codes).
- Every POST handler requires Idempotency-Key.
- Every state transition: one DB transaction = state update with version check
  + event row + outbox row.
- Act on chain events only after finality (safe block; finalized above threshold).
- Round against the user by at most one base unit; pulls round up, payouts round down.
- Custom errors and events for every contract state change; NatSpec on externals.
- Keep interfaces in contracts/src/interfaces and inherit them.

## Definition of done
- Tests pass locally and in CI; coverage of new code at least 90% lines for contracts,
  80% for services.
- Lint, typecheck, slither clean.
- Spec references in the PR description (tab and section).
```

## 4. Prompt templates

Implement a contract:

```
Context: AGENTS.md, docs/L1-smart-contracts.md.
Task: implement contracts/src/<path>.sol exactly as specified in L1 section <n>.
First write test/unit/<Name>.t.sol covering every function, role check, revert
and event in that section. Then implement. Do not add functions not in the spec.
Finish by running forge test, forge fmt, slither and reporting results.
```

Implement a backend module:

```
Context: AGENTS.md, docs/L3-backend-and-ledger.md, docs/L2-oracles-and-pricing.md.
Task: implement apps/api/src/modules/<module> per L3 section <n>.
Encode the transition table as data and generate tests from it. Use Drizzle
schema from packages/db. All money as bigint. Include integration tests with
testcontainers Postgres and Redis.
```

Implement a screen:

```
Context: AGENTS.md, docs/L5-client-apps.md, api/openapi.yaml.
Task: build <app>/<screen> per L5 section <n> using packages/ui and the generated
api-client only. Local currency first, KND second. Add a Playwright test for the
happy path and one failure path from L6 section 7 error codes.
```

Review against spec:

```
Context: AGENTS.md, the spec section, the diff.
Task: list every place the diff deviates from the spec, every spec requirement
the diff does not implement, and every test the spec implies that is missing.
Do not fix anything; report only.
```

## 5. Definition of done per task

- [ ] Tests written from the spec and passing
- [ ] No behaviour outside the spec
- [ ] Lint, typecheck, static analysis clean
- [ ] PR description names the spec tab and section
- [ ] Review-against-spec prompt run and findings resolved

## 6. Changing the spec

1. Write the change as a comment or edit in the relevant tab, with the reason.
2. If it changes a decision, add or update an ADR row in the Architecture Design.
3. Re-export the changed tab to docs/ in the repo in the same PR as the code.

Export each tab as markdown from the doc and save it under docs/ with a numbered, kebab-case name, so agents always read the current version.
