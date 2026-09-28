# L1 Smart contracts

L1 is ten contracts on Base, four of them needed for P0 and seven for P1 mainnet. The vault is the only contract that can mint, and it can only mint against assets it has actually received.

## 1. Stack and conventions

- Solidity 0.8.28, exact pragma. Foundry for build, test, scripts. OpenZeppelin Contracts and Contracts Upgradeable v5.
- UUPS proxies for KandaToken, ParticipantRegistry, BasketVault, PaymentEscrow; ERC-7201 namespaced storage; initializers disabled in constructors.
- Custom errors only, no revert strings. An event for every state change. NatSpec on every external function.
- SafeERC20 for all token moves. ReentrancyGuardTransient (Base supports transient storage) on every external function that moves tokens.
- Rounding: amounts pulled into the vault round up; amounts paid out round down. Use Math.mulDiv with explicit rounding.
- KND has 18 decimals. Basket quantities are stored as asset base units per 1e18 KND.
- Addresses of external tokens and feeds come from a per-network config file, never hard-coded.

## 2. Folder layout

```
contracts/
  src/
    token/KandaToken.sol
    registry/ParticipantRegistry.sol
    vault/BasketVault.sol
    vault/CashDesk.sol            (P2)
    payments/PaymentEscrow.sol
    oracle/NAVOracle.sol
    oracle/FXReferenceOracle.sol  (P2)
    periphery/ZapRouter.sol
    periphery/RFQSettler.sol      (P2)
    hooks/OracleBandHook.sol      (P2)
    hooks/AllowlistHook.sol       (P2)
    governance/Roles.sol
    interfaces/
    libraries/BasketMath.sol
  test/
    unit/  fuzz/  invariant/  fork/  mocks/
  script/
    Deploy.s.sol  WireRoles.s.sol  VerifyRoles.s.sol  Genesis.s.sol
  config/
    base-sepolia.json  base.json
```

## 3. Contract specifications

### 3.1 KandaToken (KND)

ERC-20 with permit (EIP-2612), transferWithAuthorization (EIP-3009), blocklist, pause, and the IBurnMintERC20 surface Chainlink CCIP pools expect.

```solidity
interface IKandaToken {
    event Blocked(address indexed account);
    event Unblocked(address indexed account);
    event Rescued(address indexed token, address indexed to, uint256 amount);
    error AccountBlocked(address account);
    error CannotRescueKnd();
    error ZeroAddress();

    // MINTER_ROLE only, whenNotPaused
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;                 // burns caller's balance
    function burnFrom(address from, uint256 amount) external; // uses allowance

    // COMPLIANCE_ROLE
    function blockAccount(address account) external;
    function unblockAccount(address account) external;
    function isBlocked(address account) external view returns (bool);

    // DEFAULT_ADMIN_ROLE
    function rescueERC20(address token, address to, uint256 amount) external;

    // PAUSER_ROLE / UNPAUSER_ROLE
    function pause() external;
    function unpause() external;

    // EIP-3009
    function transferWithAuthorization(address from, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;
    function receiveWithAuthorization(address from, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
```

Rules:

- Override \_update: revert if paused; revert AccountBlocked if from or to is blocked (mint to a blocked address also reverts).
- No seize function in P1. Frozen funds stay frozen until unblocked by the Compliance Safe on legal instruction.
- rescueERC20(token, to, amount) for tokens sent by mistake, DEFAULT\_ADMIN\_ROLE only; reverts CannotRescueKnd for KND and ZeroAddress for a zero recipient.
- Tests: every role check, blocked sender, blocked receiver, blocked spender on transferFrom, pause on every path, permit and 3009 replay protection, cancelled authorization.

### 3.2 ParticipantRegistry

Who may use the primary market and the escrow, with tiered daily limits.

```solidity
interface IParticipantRegistry {
    enum Kind { None, Participant, Partner, Both }
    struct TierLimits { uint128 dailyCreate; uint128 dailyRedeem; }
    struct Account { Kind kind; uint8 tier; bool active; uint32 day; uint128 createdToday; uint128 redeemedToday; }

    event AccountSet(address indexed account, Kind kind, uint8 tier, bool active);
    event TierSet(uint8 indexed tier, uint128 dailyCreate, uint128 dailyRedeem);
    error NotActive(address account);
    error LimitExceeded(address account, uint256 requested, uint256 remaining);
    error UnknownTier(uint8 tier);
    error ZeroAddress();

    function setAccount(address account, Kind kind, uint8 tier, bool active) external; // PARTICIPANT_MANAGER_ROLE, tier must exist (UnknownTier), account non-zero
    function setTier(uint8 tier, TierLimits calldata limits) external;                 // LIMITS_ADMIN_ROLE (timelock)
    function consumeCreate(address account, uint256 amount) external;                  // LIMITS_CONSUMER_ROLE: BasketVault (CashDesk in P2)
    function consumeRedeem(address account, uint256 amount) external;                  // LIMITS_CONSUMER_ROLE: BasketVault
    function isParticipant(address account) external view returns (bool);
    function isPartner(address account) external view returns (bool);
    function remaining(address account) external view returns (uint256 create, uint256 redeem);
}
```

Day index is block.timestamp / 1 days (UTC). Counters reset lazily when the stored day differs from today.

A tier exists once setTier has been called for it. Consumers are authorized by LIMITS\_CONSUMER\_ROLE, granted by WireRoles, because the registry is deployed before the vault (section 7).

### 3.3 BasketVault

Holds reserves and runs in-kind create and redeem. Sole MINTER\_ROLE holder in P1.

```solidity
interface IBasketVault {
    struct Leg { address asset; uint256 qtyPerUnit; } // asset base units per 1e18 KND

    event Created(address indexed participant, address indexed to, uint256 kndGross, uint256 fee, uint256[] amountsIn);
    event Redeemed(address indexed participant, address indexed to, uint256 kndGross, uint256 fee, uint256[] amountsOut);
    event BasketVersionSet(uint32 indexed version, Leg[] legs);
    event SupplyCapSet(uint256 cap);
    event FeeSet(uint16 feeBps, address recipient);
    event CreatePaused(address account);
    event CreateUnpaused(address account);

    error SupplyCapExceeded(uint256 newSupply, uint256 cap);
    error SlippageOut(uint256 leg, uint256 amount, uint256 min);
    error MintBelowMin(uint256 minted, uint256 minOut);
    error BasketNotBacked(uint256 leg);
    error CreationPaused();
    error FeeTooHigh(uint16 feeBps);
    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch(uint256 expected, uint256 actual);
    error InvalidBasket();

    function createInKind(uint256 kndAmount, uint256 minKndOut, address to) external returns (uint256 kndOut);
    function redeemInKind(uint256 kndAmount, uint256[] calldata minAmountsOut, address to) external returns (uint256[] memory amountsOut);
    function previewCreate(uint256 kndAmount) external view returns (uint256[] memory amountsIn, uint256 kndOutNet);
    function previewRedeem(uint256 kndAmount) external view returns (uint256[] memory amountsOut);
    function legs() external view returns (uint32 version, Leg[] memory);
    function coverage() external view returns (uint256[] memory ratiosBps); // per leg, 10000 = 100%
    function createPaused() external view returns (bool);

    function setSupplyCap(uint256 cap) external;                 // LIMITS_ADMIN_ROLE
    function setFee(uint16 feeBps, address recipient) external;  // LIMITS_ADMIN_ROLE, feeBps <= 100 (FeeTooHigh)
    function pause() external;          // PAUSER_ROLE: stops create and redeem
    function unpause() external;        // UNPAUSER_ROLE
    function pauseCreate() external;    // PAUSER_ROLE: stops create only; redeem continues
    function unpauseCreate() external;  // UNPAUSER_ROLE
    // setBasket(uint32 version, Leg[] legs): deferred to P3 (ADR-012, task T3.2)
}
```

createInKind, in order:

1. Require the vault not paused and creation not paused (CreationPaused); kndAmount non-zero (ZeroAmount); to non-zero (ZeroAddress) and not blocked; caller is an active participant.
2. For each leg compute required = mulDiv(kndAmount, qtyPerUnit, 1e18, Ceil); pull it with safeTransferFrom; record received as the balance delta.
3. kndGross = minimum over legs of mulDiv(received, 1e18, qtyPerUnit, Floor), capped at kndAmount. This handles fee-on-transfer gold tokens: the scarcest leg decides; any excess stays as surplus backing.
4. Check totalSupply + kndGross against the supply cap; call registry.consumeCreate.
5. fee = mulDiv(kndGross, feeBps, 10000, Ceil); mint kndGross minus fee to to and fee to the fee recipient; require net at or above minKndOut.

redeemInKind, in order:

1. Require the vault not paused (a creation pause does not apply); kndAmount non-zero; to non-zero; minAmountsOut has one entry per leg (LengthMismatch); caller is an active participant; call registry.consumeRedeem.
2. Pull kndAmount from caller; fee in KND goes to fee recipient; burn the rest (net).
3. For each leg pay mulDiv(net, qtyPerUnit, 1e18, Floor); check against minAmountsOut; transfer to to.

The genesis basket is set once by initialize from config (version 1, BasketVersionSet emitted). initialize reverts InvalidBasket if the legs are empty, any asset is zero or repeated, or any qtyPerUnit is zero. setBasket is deferred to P3 (ADR-012); when added it must check every new leg is already fully backed for current supply, so a switch can never leave KND under-collateralized.

Pause model (ADR-011): pausing KandaToken stops every KND movement, including the burn inside redeem. The response to a reserve-asset depeg is pauseCreate on the vault, which leaves redeem open. A pause or blacklist on a reserve token itself (USDC or DGLD) makes every create and redeem revert, because both move every leg.

### 3.4 PaymentEscrow

Locks KND per payment intent between two registered partners.

```solidity
interface IPaymentEscrow {
    enum Status { None, Locked, Released, Refunded, Disputed, Resolved }
    struct Intent { address sender; address receiver; uint128 amount; uint64 expiry; Status status; bytes32 metadataHash; }

    event Locked(bytes32 indexed intentId, address indexed sender, address indexed receiver, uint128 amount, uint64 expiry, bytes32 metadataHash);
    event Released(bytes32 indexed intentId, address indexed by);
    event Refunded(bytes32 indexed intentId, address indexed by);
    event Disputed(bytes32 indexed intentId, address indexed by);
    event Resolved(bytes32 indexed intentId, uint128 toReceiver, uint128 toSender);

    error IntentExists(bytes32 intentId);
    error BadStatus(bytes32 intentId, Status status);
    error NotExpired(bytes32 intentId);
    error Unauthorized(address caller);
    error BadExpiry(uint64 expiry);
    error InvalidExpiryBounds(uint64 minExpiry, uint64 maxExpiry);
    error InvalidSplit(uint128 toReceiver, uint128 amount);
    error SameParty(address account);
    error ZeroAmount();

    event ExpiryBoundsSet(uint64 minExpiry, uint64 maxExpiry);

    function lock(bytes32 intentId, address receiver, uint128 amount, uint64 expiry, bytes32 metadataHash) external;
    function release(bytes32 intentId) external;  // sender or RELEASER_ROLE, status Locked
    function reject(bytes32 intentId) external;   // receiver, status Locked, refunds sender now
    function refund(bytes32 intentId) external;   // anyone after expiry, status Locked
    function dispute(bytes32 intentId) external;  // sender or receiver, status Locked, before expiry
    function resolve(bytes32 intentId, uint128 toReceiver) external; // ARBITER_ROLE, status Disputed, toReceiver <= amount (InvalidSplit)
    function setExpiryBounds(uint64 minExpiry, uint64 maxExpiry) external; // LIMITS_ADMIN_ROLE (timelock)
    function pause() external;    // PAUSER_ROLE
    function unpause() external;  // UNPAUSER_ROLE
    function batchRelease(bytes32[] calldata ids) external; // P2
    function intents(bytes32 intentId) external view returns (Intent memory);
}
```

- intentId = keccak256 of the off-chain intent UUID and the chain id, computed by the backend; reuse reverts.
- expiry must fall between now plus minExpiry (15 minutes) and now plus maxExpiry (24 hours); initial values from config, changed by setExpiryBounds through the timelock; InvalidExpiryBounds unless 0 < minExpiry <= maxExpiry.
- metadataHash = keccak256 of the canonical JSON of the Travel Rule and invoice payload stored off-chain.
- Sender and receiver must be active partners and must differ (SameParty); neither may be blocked; amount is non-zero (ZeroAmount).
- While the escrow is paused, every state-changing function reverts (INV-7).

### 3.5 NAVOracle

Non-upgradeable. NAV = usdLeg + G times gold price, 18 decimals.

```solidity
interface INAVOracle {
    enum Health { Ok, Degraded, Down }
    function nav() external view returns (uint256 navUsd, uint256 updatedAt, Health health);
    function navStrict() external view returns (uint256 navUsd); // reverts unless Ok
}
```

- Inputs: primary gold feed, secondary feed, Base L2 sequencer uptime feed with a 1-hour grace period, maxStaleness (for example 1 hour plus heartbeat), maxDeviationBps between feeds (for example 100).
- Ok: both feeds fresh, sequencer up, deviation within bound; returns the primary. Degraded: one feed usable; returns it. Down: neither usable or sequencer down.
- Used by ZapRouter, hooks and the backend. Never used by BasketVault.

### 3.6 ZapRouter

Lets a registered participant or partner create KND with USDC only.

```solidity
function zapCreate(uint256 usdcIn, uint256 minKndOut, uint256 maxPremiumBps, bytes calldata swapData, uint256 deadline, address to) external returns (uint256 kndOut);
```

Pulls USDC, swaps the gold-leg share through an allowlisted router only (swapData is decoded, not called blindly), calls createInKind as a registered participant with its own limits, checks the effective price against navStrict within maxPremiumBps, refunds leftovers, sends KND to to.

### 3.7 OracleBandHook (P2)

Uniswap v4 hook with beforeSwap and afterSwap permissions on dynamic-fee pools. Reference price = NAV for KND/USDC and NAV times the FX reference for KND/local-stable pools. beforeSwap sets a fee that rises as the pool price moves away from the reference; afterSwap reverts if the post-swap price leaves the hard band (for example 1% for USDC pools, 3% for local pools). If the oracle is Down the hook widens to a fallback fee instead of blocking, to avoid freezing liquidity.

AllowlistHook, for institutional pools, checks the end user through trusted routers that expose msgSender; untrusted routers are rejected.

### 3.8 RFQSettler (P2)

Settles EIP-712 quotes signed by registered market makers: maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce, expiry. Nonces are a per-maker bitmap. Both legs move atomically with transferFrom. Makers must be registered; blocked addresses rejected.

### 3.9 Cross-chain with CCIP (P2)

Base is the home chain and uses a LockRelease token pool, so Base totalSupply always equals global supply and INV-1 stays exact. Celo and Avalanche use BurnMint pools with the same KandaToken code, where only the pool holds MINTER\_ROLE. Rate limits per lane (capacity and refill rate) are set by the timelock. Reconciliation: Base pool locked balance equals the sum of remote supplies plus in-flight messages.

### 3.10 CashDesk (P2)

Mints and burns against off-chain reserves. Two-step: Ops Safe requests, Treasury Safe approves. Mint only if, for each leg, vault balance plus attested off-chain holding (from a proof-of-reserve feed per leg) covers (supply plus amount) times quantity. Daily limit set by timelock. INV-1 becomes vault plus attested holdings.

## 4. Parameters

| Parameter | Contract | Setter | P1 default |
| --- | --- | --- | --- |
| supplyCap | BasketVault | Timelock | 1,000,000e18 |
| feeBps | BasketVault | Timelock | 10 |
| Tier 1 limits | Registry | Timelock | 50,000e18 create, 50,000e18 redeem per day |
| Tier 2 limits | Registry | Timelock | 250,000e18 each |
| minExpiry, maxExpiry | PaymentEscrow | Timelock | 15 min, 24 h |
| maxStaleness | NAVOracle | Redeploy | feed heartbeat plus 10% |
| maxDeviationBps | NAVOracle | Redeploy | 100 |
| Legs | BasketVault | Genesis (initializer); P3 reconstitution | USDC 700000 per 1e18 KND; DGLD G x 1e18 per 1e18 KND (18 decimals, 1 DGLD = 1 troy oz) |

Gold token (ADR-010, accepted 27 Sep 2026): DGLD on Base, 0xe908475f8Beb7A138B0dc6eb5A05cb27068ffB9A, issued by Gold Token SA. Checked on-chain on 27 Sep 2026:

- 18 decimals, behind an upgradeable proxy. The V3 transfer path charges no fee, but an upgrade could add one, so the vault keeps measuring balance deltas.
- The issuer can pause all transfers, blacklist an address, and move a blacklisted address's balance to its recovery address. Monitoring alerts on these events for the vault (L7 section 5, R5).
- No EIP-2612 permit: participants approve DGLD before createInKind.
- 1 DGLD = 1 troy ounce, inferred from its price matching XAU/USD. Confirm in the issuer's terms (on-chain tcURL) before genesis; if the unit is a gram, qtyPerUnit is G x 31.1034768 x 1e18.
- Liquidity: about 401 DGLD circulated on Base with about 1,100 holders. At the P1 cap, the gold leg needs about 70 DGLD. Confirm authorized participants' sourcing (issuer mint or bridge) and DEX pool depth before the zap parameters are set.

## 5. Invariant test suite

Handler-based Foundry invariants in test/invariant/. The handler exposes: create, redeem, transfer, transferFrom, lock, release, reject, refund after time warp, dispute, resolve, pause and unpause on each contract, pauseCreate, unpauseCreate, block, unblock, and fee-on-transfer, pause and blacklist toggles on the mock gold token (modelled on DGLD). Ghost variables track expected escrow balance and per-day consumption.

| Invariant | Assertion |
| --- | --- |
| INV-1 | For every leg, balanceOf(vault) at least ceil(totalSupply times qty / 1e18) |
| INV-2 | totalSupply at most supplyCap |
| INV-3 | Supply changes only inside vault calls (ghost counter) |
| INV-4 | KND.balanceOf(escrow) equals the ghost sum of Locked and Disputed amounts |
| INV-5 | Terminal intents never change (ghost snapshot) |
| INV-6 | Consumed per day at most tier limit |
| INV-7 | Handler calls blocked by any pause (token, vault, vault creation, escrow) never change balances |
| INV-8 | Blocked accounts' balances never change |

CI runs 256 runs on pull requests and 10,000 runs at depth 100 nightly.

## 6. Test plan

| Level | What | Tooling |
| --- | --- | --- |
| Unit | Every function, role, revert and event | forge test |
| Fuzz | Amount and rounding edges, fee-on-transfer, decimals 6 and 18 | forge fuzz, 10,000 runs |
| Invariant | Section 5 | forge invariant |
| Fork | Real USDC, gold token and Chainlink feeds on Base | forge test with fork URL |
| Upgrade | Storage layout checks between versions | OZ upgrades validation, forge inspect |
| Static | Slither, Aderyn; zero high findings | CI |
| Gas | Snapshot per function; regressions over 5% fail CI | forge snapshot |

## 7. Deployment

Deploy.s.sol reads config/\<network>.json, deploys in this order and writes deployments/\<network>.json:

1. TimelockController (proposer and canceller: Admin Safe; executor: open).
2. KandaToken proxy.
3. ParticipantRegistry proxy.
4. BasketVault proxy with legs from config.
5. NAVOracle.
6. PaymentEscrow proxy.
7. ZapRouter.
8. WireRoles.s.sol grants every role in the ADD role map, then renounces all deployer roles.
9. VerifyRoles.s.sol reads every role on every contract and fails if anything differs from the map.

```json
{
  "chainId": 84532,
  "usdc": "0x...",
  "goldToken": "0x...",
  "goldDecimals": 18,
  "goldFeedPrimary": "0x...",
  "goldFeedSecondary": "0x...",
  "sequencerFeed": "0x...",
  "safes": { "admin": "0x...", "ops": "0x...", "compliance": "0x...", "guardian": "0x...", "treasury": "0x..." },
  "pauseBot": "0x...",
  "releaser": "0x...",
  "feeRecipient": "0x...",
  "timelockDelay": 300,
  "supplyCap": "1000000000000000000000000",
  "feeBps": 10,
  "usdQtyPerUnit": "700000",
  "goldQtyPerUnit": "set at genesis",
  "tiers": [
    { "tier": 1, "dailyCreate": "50000000000000000000000", "dailyRedeem": "50000000000000000000000" },
    { "tier": 2, "dailyCreate": "250000000000000000000000", "dailyRedeem": "250000000000000000000000" }
  ],
  "escrow": { "minExpiry": 900, "maxExpiry": 86400 },
  "nav": { "maxStaleness": 95040, "maxDeviationBps": 100 },
  "zap": { "routers": [] }
}
```

Deploy.s.sol aborts if goldDecimals differs from goldToken.decimals(). nav.maxStaleness is the feed heartbeat plus 10% (86,400 s for XAU/USD on Base).

## 8. Security checklist before audit

- [ ] No function lets any role mint without receiving basket assets (except CashDesk in P2 with PoR gating)
- [ ] Every external token call uses SafeERC20 and balance deltas
- [ ] Reentrancy guards on all token-moving functions; checks, effects, interactions order
- [ ] Pause blocks every value path, including escrow
- [ ] Initializers protected; implementation constructors disable initializers
- [ ] Storage layouts namespaced; upgrade tests pass
- [ ] Oracle staleness, sequencer check and deviation checks covered by tests
- [ ] Signature replay protection (permit, 3009, RFQ) tested, including cross-chain replay via chain id
- [ ] Role map verified by script on every deployment

## 9. Rules for your coding agent

- Implement one contract per task with its full test file; do not start the next contract until tests and slither pass.
- Never add a function that is not in this spec; propose it as a spec change first.
- Never use revert strings, tx.origin, floating pragma, or unchecked math outside audited loops.
- Keep every interface in src/interfaces and make contracts inherit them so the spec and code cannot drift.
