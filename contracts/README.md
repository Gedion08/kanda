# contracts (L1)

Foundry project for KND, BasketVault, ParticipantRegistry, PaymentEscrow, NAVOracle and ZapRouter.
Spec: `docs/L1-smart-contracts.md`. Rules: `AGENTS.md` (custom errors only, exact pragma `0.8.28`,
interfaces in `src/interfaces` and inherited, no oracle reads in BasketVault).

```sh
forge soldeer install      # dependencies pinned in foundry.toml
forge fmt --check
forge build --sizes
forge test                 # PR profile: fuzz 10,000, invariant 256 runs
FOUNDRY_PROFILE=ci forge test --match-path 'test/invariant/*'   # nightly: 10,000 runs, depth 100
slither .                  # config in slither.config.json, fails on high
```

`config/<network>.json` holds per-network addresses and parameters (never hard-code them).
Placeholders are zero addresses until the key ceremony. `Deploy.s.sol` writes `deployments/<network>.json`,
which the indexer and `packages/chain` read.

`test/unit/ToolchainSmoke.t.sol` exists only so CI is green before T0.2; delete it then.
