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

`Deploy.s.sol` refuses to run if the config's chain ID doesn't match, any address is still a zero placeholder,
`goldDecimals` differs from the gold token, or `goldQtyPerUnit` is unset.

## Deploying

Keys live outside the repo, in `~/.kanda/` with owner-only permissions. Never in `.env` files here (AGENTS.md).

```sh
set -a; . ~/.kanda/base-sepolia.env; set +a
RPC=$BASE_SEPOLIA_RPC_URL

# Testnet only, once: five 1-of-1 Safes owned by the deployer, plus testnet USDC and gold.
forge script script/testnet/SetupTestnet.s.sol --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --broadcast
#   then copy deployments/base-sepolia-setup.json into config/base-sepolia.json

# Rehearse on a fork first: anvil --fork-url $RPC --port 8546, then run the lines below against it.
forge script script/Deploy.s.sol --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --broadcast --slow
forge script script/VerifyRoles.s.sol --rpc-url $RPC      # read-only; reverts RoleMismatch on any drift
SEED_KND=1000 forge script script/testnet/SeedTestnet.s.sol --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --broadcast --slow

# Source verification, one contract at a time (Blockscout rate-limits bursts; Sourcify needs no key):
forge verify-contract <address> <path>:<Contract> --chain 84532 --rpc-url $RPC --guess-constructor-args --verifier sourcify
```

## Base Sepolia (chain 84532), deployed 28 Sep 2026

| Contract | Address |
| --- | --- |
| KandaToken (proxy) | `0x10E0caD60b43b1919238918CF00F06ebBfE118cf` |
| ParticipantRegistry (proxy) | `0xD9289B314C25a5C28409FA5f5C51e7Cbe58d5b42` |
| BasketVault (proxy) | `0xd28b639C40bb0cbA4ce98684915cb8dEcEb81db3` |
| TimelockController (5-minute delay) | `0xC0C377Eb76d12F5C432A1C7F126ab119407168b2` |
| Testnet USDC (tUSDC, 6 decimals) | `0xCb0586c74234fa79f8a71f926841B3d1ae9E6c98` |
| Testnet gold (tDGLD, 18 decimals) | `0x2BF116ed7190147A90219271361dE9477Fb7B4E8` |
| Admin / Ops / Compliance / Guardian / Treasury Safes | see `config/base-sepolia.json` |

Implementations and the start block are in `deployments/base-sepolia.json`. All sources are verified (Blockscout
and Sourcify). VerifyRoles passes, and the deployer holds no role. SeedTestnet created 1,000 KND, and coverage is
10000 bps on both legs.

**Testnet caveats.** Each Safe is 1-of-1, owned by the deployer, so one key controls every role until you add
signers. In the Safe app (app.safe.global, Base Sepolia), open each Safe, go to Settings → Setup, add owners, and
raise the threshold toward the ADD section 4 targets: Admin 3 of 5, Guardian 2 of 4, Ops and Compliance 2 of 3.
The Safe addresses don't change. `goldQtyPerUnit` is a testnet G of 0.00007 oz per KND (about 30% of 1 USD at
4,285 USD/oz). The real G is fixed at mainnet genesis. The deployer key has been shared in a chat transcript: it is
testnet-only, and mainnet uses a fresh deployer at the key ceremony (L7 section 2).
