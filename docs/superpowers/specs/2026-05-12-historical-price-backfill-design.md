# Historical Price Backfill Design

## Summary

Portu should use local snapshots as the source of truth for portfolio history and use CoinGecko historical prices as separate reference data. A manual Settings action will fetch and cache daily USD price history for known CoinGecko assets. Charts use that cache for asset price history, period price changes, and clearly labeled estimated portfolio values before the first real Portu snapshot when the user enables backfill.

## Goals

- Keep `PortfolioSnapshot`, `AccountSnapshot`, and `AssetSnapshot` authoritative and unmodified by backfill.
- Add a separate historical price cache that can be refreshed or cleared without changing observed portfolio history.
- Let the user manually trigger backfill from Settings so larger CoinGecko fetches are explicit.
- Use estimated portfolio values only before the first real snapshot, based on the earliest known holdings.
- Make estimated chart points visually distinct from real snapshot-derived points.
- Support Asset Detail price charts and Performance asset price changes from cached CoinGecko history.

## Non-Goals

- Do not generate estimated `PortfolioSnapshot`, `AccountSnapshot`, or `AssetSnapshot` rows.
- Do not infer deposits, withdrawals, trades, or historical DeFi position changes from CoinGecko data.
- Do not claim estimated backfill is actual P&L.
- Do not add another market data provider in this version.
- Do not build automatic background backfill in this version.

## CoinGecko Capability

CoinGecko provides historical market chart endpoints by coin ID:

- `/coins/{id}/market_chart` for a relative day range.
- `/coins/{id}/market_chart/range` for a Unix timestamp range.

The responses include timestamped prices, market caps, and volumes. Portu only needs USD prices for this feature. The implementation should request daily data for backfill where supported and tolerate CoinGecko's automatic data granularity. CoinGecko rate limits can vary by plan and traffic, so the app should use the stored CoinGecko API key when available and otherwise use conservative public API pacing.

References checked on 2026-05-12:

- [CoinGecko market chart endpoint](https://docs.coingecko.com/reference/coins-id-market-chart)
- [CoinGecko market chart range endpoint](https://docs.coingecko.com/reference/coins-id-market-chart-range)
- [CoinGecko common errors and rate limits](https://docs.coingecko.com/docs/common-errors-rate-limit)

## Data Model

Add a SwiftData model in `PortuCore` for cached historical prices.

Suggested model: `HistoricalPricePoint`.

Fields:

- `id`
- `coinGeckoId`
- `day`, normalized to the start of the UTC calendar day
- `usdPrice`
- `source`, with `coingecko` as the only source in this version
- `fetchedAt`

The logical dedupe key is `(coinGeckoId, day)`. A repeated backfill updates the existing row's `usdPrice` and `fetchedAt`.

This model is reference data, not user portfolio data. It should not relate to `AssetSnapshot` directly because the same CoinGecko ID can be reused by many asset snapshots and because cache rows should survive portfolio data changes.

## Package Ownership

- `PortuNetwork` fetches and parses CoinGecko historical price responses.
- `PortuCore` owns historical price DTOs and the SwiftData cache model.
- The app target owns candidate asset selection, Settings UI, SwiftData cache writes, and chart estimate derivation.
- `PortuUI` remains presentation-only.

This preserves the existing layering:

- `PortuUI -> PortuCore`
- `PortuNetwork -> PortuCore`
- App target imports all packages.

## Settings UX

Add a `Historical Prices` section to the General settings tab.

Controls:

- Toggle: `Use historical price backfill`
- Button: `Backfill historical prices`
- Status row: last successful fetch time, covered asset count, skipped asset count, and latest failure summary
- Button: `Clear historical price cache`

The CoinGecko API key remains in API Keys. The General tab controls whether and when Portu uses historical price cache data.

## Backfill Workflow

1. User clicks `Backfill historical prices`.
2. App builds a candidate list from active holdings that have a resolved CoinGecko ID.
3. Candidate resolution should prefer a user CoinGecko ID override over provider metadata.
4. Manual-only prices and assets without a CoinGecko ID are skipped.
5. App fetches daily USD history for a one-year horizon.
6. App writes or updates `HistoricalPricePoint` rows by `(coinGeckoId, day)`.
7. Settings displays success, partial success, rate limit, or failure state.

The run is allowed to be partially successful. Already fetched assets stay cached even if later assets fail.

## Chart Behavior

Real chart data continues to come from local snapshots.

Estimated chart data is derived at render time:

1. Find the earliest real snapshot for the selected scope.
2. Use the asset amounts from that earliest snapshot as fixed estimated holdings.
3. For dates before that snapshot, multiply each fixed amount by the cached CoinGecko price for that asset's day.
4. Sum assets into estimated portfolio or account values.
5. Stop estimated points at the first real snapshot day.

Overview value chart:

- Real values use `PortfolioSnapshot`.
- Estimated values can be prepended when the setting is enabled and cache data exists.
- Estimated segment uses a subdued dashed style and a clear label.

Performance value chart:

- Uses the same split between estimated and real values.
- Account filters use account-scoped earliest asset snapshots.

Performance PnL chart:

- Initially uses real snapshots only.
- Estimated values are excluded from PnL to avoid implying actual historical returns.

Performance asset prices:

- Uses cached historical prices to show period price change for top assets.

Asset Detail price chart:

- Uses cached `HistoricalPricePoint` rows for the asset's CoinGecko ID.
- If cache is missing, the chart shows a clear empty state and directs the user to run backfill.

## Error Handling

- Rate limit or HTTP 429: stop the current run, keep successful rows, and show a rate-limit status.
- Network failure: keep successful rows and show a retryable failure status.
- Invalid response or decoding failure: record the failed CoinGecko ID and continue when possible.
- Missing CoinGecko ID: skip and count the asset as skipped.
- No snapshots: asset price charts can still use cached prices, but estimated portfolio history is unavailable.
- Cache clear failure: show an error and leave existing rows untouched.

## Testing

PortuNetwork tests:

- Historical market chart URL construction.
- Parsing timestamped CoinGecko price arrays.
- Handling malformed and partial payloads.
- Mapping HTTP 429 to `PriceServiceError.rateLimited`.

PortuCore tests:

- `HistoricalPricePoint` stores day-level USD prices.
- Dedupe identity is `(coinGeckoId, day)`.
- DTOs and model-facing value types are `Sendable` where needed.

App tests:

- Backfill candidate selection prefers CoinGecko ID overrides.
- Assets without CoinGecko IDs are skipped.
- Manual-only prices are not backfilled.
- Repeated backfill updates existing cache rows.
- Estimated portfolio derivation uses earliest snapshot holdings.
- Estimated chart points stop before the first real snapshot.
- PnL excludes estimated points.
- Chart data sorting is deterministic by day, then stable secondary keys where applicable.

Settings tests:

- Toggle persists in local settings.
- Manual backfill button reports loading, success, partial success, and failure states.
- Clear cache removes only historical price rows.
