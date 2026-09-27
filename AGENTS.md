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
