# L2 Oracles and pricing

Kanda needs three prices: KND's NAV in USD, a reference rate for each local currency, and the all-in customer quote. Only NAV lives on-chain in P1; no price ever gates minting or burning.

## 1. Price map

| Price | Used for | Source | Update | If it fails |
| --- | --- | --- | --- | --- |
| Gold in USD | NAV | Chainlink XAU/USD or PAXG/USD on Base, secondary feed | Feed heartbeat | NAV Degraded or Down; zap off; in-kind unaffected |
| NAV (USD per KND) | Display, zap bound, pool bands, quotes | NAVOracle and NAV service | Every block on-chain, every minute off-chain | Banner in apps; quotes switch to partner-only pricing with wider hold threshold |
| Local currency per USD, reference | Quote checks, monitoring, regulator reports | Partner quotes, central bank official rate, market indicators | Minutes to daily | Corridor paused for new quotes if no source is fresh |
| Partner rate (local per KND) | Customer quotes | Partner quote endpoint, signed | Per request, valid up to 60 s | Quote fails with a retryable error |
| All-in quote | Customer | Quote service | Per request, locked 10 min | Expired quotes cannot be confirmed |

## 2. NAV

- Formula: NAV = 0.70 + G times gold price (USD per ounce), 18-decimal fixed point.
- On-chain: NAVOracle per L1 section 3.5, including the L2 sequencer uptime check.
- Off-chain NAV service reads the same feeds through viem, recomputes NAV, and stores a NAVSnapshot every minute: navUsd, goldPrice, feedRoundIds, health.
- Cross-check: compare against an independent spot source; alert if the gap exceeds 50 bps for 5 minutes.
- Confirm feed availability and addresses on Base in P0 (open decision). If only a PAXG/USD feed exists, record that PAXG can trade slightly away from spot gold and treat 50 bps as the tolerance.

## 3. FX reference

Kanda never sets a local rate; it builds a reference to check partner quotes against and to show regulators what was used.

Sources per currency:

| Source | Example | Role |
| --- | --- | --- |
| Partner quotes | Kenyan partner's KES per KND buy and sell | Primary for customer pricing |
| Official rate | Published central bank rate for KES, NGN | Reference and reporting |
| Market indicators | Bank and exchange mid rates, P2P stablecoin rates | Detects parallel-market gaps; recorded, not imposed |

Reference mid = median of fresh independent sources after trimming outliers beyond 5% of the provisional median.

Regime flag per currency: if official and market indicators differ by more than a corridor threshold (for example 5%) for 24 hours, the currency enters Parallel regime. Quotes still flow, but each quote records the partner's declared rate basis (official or market), the hold threshold uses the source the partner declares, and the compliance team is notified.

On-chain from P2:

```solidity
interface IFXReferenceOracle {
    enum Regime { Normal, Parallel, Suspended }
    struct Rate { uint256 localPerUsd; uint64 updatedAt; uint8 sources; Regime regime; }
    event Reported(bytes3 indexed currency, address indexed reporter, uint256 localPerUsd, uint64 observedAt);
    function report(bytes3 currency, uint256 localPerUsd, uint64 observedAt, bytes calldata sig) external; // registered reporters, EIP-712
    function setRegime(bytes3 currency, Regime regime) external; // ORACLE_ADMIN_ROLE
    function rate(bytes3 currency) external view returns (Rate memory);
}
```

The on-chain median uses the latest report from each reporter within a freshness window; fewer than three fresh reporters marks the rate Suspended for pool bands.

## 4. Quote service

Steps for a quote request (sendCurrency, receiveCurrency, amount, amountSide):

1. Validate corridor is open, amount within business and corridor limits.
2. Request signed quotes in parallel from the sending partner (buy KND with send currency) and receiving partner (sell KND for receive currency); timeout 500 ms each.
3. Verify signatures, validity windows and maximum amounts.
4. Compare each partner rate with the reference converted through NAV (local per KND = local per USD times NAV). Outside the corridor threshold: return a quote in Held state for manual approval instead of failing silently.
5. Compute the all-in quote with the ADD formula, using bigint fixed point: amounts in base units, rates scaled 1e18, round against the customer by at most one base unit.
6. Store the quote with the partner quote ids and lock it for 10 minutes; partners must honor locked quotes contractually.

Quote object:

```json
{
  "id": "qt_01J...",
  "corridor": "KE-NG",
  "send": { "currency": "KES", "amount": "1290000.00" },
  "receive": { "currency": "NGN", "amount": "15320000.00" },
  "knd": "9812.450000000000000000",
  "rates": { "sendPerKnd": "131.47", "receivePerKnd": "1561.30", "navUsd": "1.0231" },
  "fees": { "sendPartner": "2580.00", "network": "3870.00", "receivePartner": "0.00" },
  "rateBasis": { "send": "official", "receive": "market" },
  "status": "locked",
  "expiresAt": "2026-10-01T10:10:00Z"
}
```

The numbers above are illustrative only.

Hold policy:

| Condition | Action |
| --- | --- |
| Partner rate outside threshold vs reference | Quote Held; ops approve or reject within 15 min |
| NAV health Degraded | Quote allowed, threshold widened by 50%, banner shown |
| NAV health Down | New quotes blocked for the corridor |
| Reference has no fresh source | New quotes blocked for that currency |
| Currency in Parallel regime | Quote allowed with declared rate basis; compliance notified daily |

Partner quote endpoint contract (partner implements it):

```
GET {partnerBase}/kanda/v1/quote?currency=KES&side=buy&amount=1290000.00
200 { "quoteId": "...", "localPerKnd": "131.47", "maxAmount": "5000000.00", "validUntil": "...", "rateBasis": "official", "signature": "..." }
```

## 5. Monitoring

- Feed staleness, sequencer status, NAV on-chain vs off-chain gap.
- Per currency: reference freshness, number of sources, official-market gap, regime.
- Per partner: quote latency, rejection rate, share of held quotes, locked quotes not honored.

## 6. Tests

- Unit: formula with rounding, every hold condition, signature verification, expiry.
- Property: quote receive amount is monotonic in send amount; fees never negative.
- Fork: NAVOracle health states with warped timestamps and a mocked sequencer feed.
- Replay: yesterday's partner quotes and reference data replayed through the service must give identical results.

## 7. Agent tasks

1. Build packages/pricing: fixed-point helpers (bigint, 1e18), NAV formula, quote formula, with property tests.
2. Build the NAV service module and NAVSnapshot writer.
3. Build the FX reference module with source adapters behind one interface; start with partner quotes and one official-rate adapter per currency.
4. Build the quote module, hold policy and Redis locking.
5. P2: implement FXReferenceOracle and a reporter service signing EIP-712 reports.
