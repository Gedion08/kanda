# Transparency page (L5 section 5, T0.7)

A static site that reads KND supply, vault reserves, coverage, pause state, Safes, the role map and contract
addresses straight from the chain, at a single block, through a public RPC and Multicall3. No Kanda backend is
involved, so it keeps working if ours are down. Addresses come from `contracts/deployments` and `contracts/config`
through `@kanda/chain`.

```sh
pnpm --filter @kanda/transparency dev       # http://localhost:5173
pnpm --filter @kanda/transparency build     # static files in dist/
pnpm --filter @kanda/transparency test
KANDA_LIVE=1 pnpm --filter @kanda/transparency test   # also reads the live Base Sepolia deployment
```

`VITE_RPC_URL` overrides the public Base Sepolia RPC (use a keyed provider for real traffic).

**Not public yet.** The page uses the Kanda logo, and the brand is internal until the name clears and counsel has
reviewed the token texts (`docs/review/p0-exit-gate.md`, section 4). Run it locally or behind access control until then.

In P1: NAV and gold feeds (NAVOracle), history charts and the timelock queue (indexer).
