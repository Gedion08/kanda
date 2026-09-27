# Kanda

KND is a reserve-backed basket token (1 KND = 0.70 USD + G oz gold) on Base. Around it sits a partner network that settles cross-border payments through an on-chain escrow.

- Specs: [`docs/`](docs/). Precedence: `02-architecture-design.md`, then the layer spec (`L1`–`L7`), then the phase tab.
- Agent rules: [`AGENTS.md`](AGENTS.md). How to work: [`docs/05-build-playbook.md`](docs/05-build-playbook.md).
- Pre-implementation review and proposed spec changes: [`docs/review/`](docs/review/).

## Layout

```
contracts/        Foundry (L1): src/ test/{unit,fuzz,invariant,fork,mocks} script/ config/ deployments/
apps/api          Hono modular monolith and BullMQ workers (L3)
apps/indexer      Ponder (L3)
apps/transparency Public reserves page, reads chain directly (L5, first app: T0.7)
apps/business  apps/partner  apps/admin   (L5, P1)
apps/mobile       P2, not yet a workspace package
packages/shared   money/decimal helpers, error codes, types
packages/pricing  fixed-point NAV and quote math (L2)
packages/db       Drizzle schema and migrations (L3, L4)
packages/chain    ABIs, addresses, viem clients, tx submitter
packages/ui  packages/api-client  packages/sdk
api/openapi.yaml  Partner API source of truth (L6)
infra/            Terraform (L7)
```

Dependency direction: `apps/* -> packages/*`. `shared` depends on nothing. `sdk` is published, so it must never import `db` or `chain`.

## Toolchain

| Tool         | Version                    | Notes                                |
| ------------ | -------------------------- | ------------------------------------ |
| Node         | 22 LTS (`.nvmrc`)          | `nvm use`                            |
| pnpm         | 10.34.5 (`packageManager`) | `corepack enable`                    |
| Foundry      | 1.8.3                      | `foundryup -i 1.8.3`                 |
| Solidity     | 0.8.28, EVM `cancun`       | exact pragma                         |
| OpenZeppelin | 5.6.1 (Soldeer)            | contracts and contracts-upgradeable  |
| TypeScript   | 6.0.x                      | held below 6.1 for typescript-eslint |

## Commands

```sh
corepack enable && pnpm install
pnpm lint && pnpm typecheck && pnpm test && pnpm format:check

cd contracts
forge soldeer install
forge fmt --check && forge build && forge test
```

CI (`.github/workflows/ci.yml`) runs the same steps on every PR.
