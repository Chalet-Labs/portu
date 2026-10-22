# Portfolio Read Model Behavioral Spec

## Terms

- **Store**: the app's SwiftData container.
- **Projection**: the `PortfolioProjection` value. It is `Sendable` and `Equatable`, holds no model, and survives deletion of the rows it was built from.
- **Projector**: the read-only `@ModelActor` that builds a projection from the store.
- **Revaluation**: one call of the `PortfolioValuator`, which produces the whole valued output (V2) from the projection, the price inputs, the settings and the watchlist.
- **Price inputs**: `AppFeature.State.livePricesUSD`, `priceChanges24h` and `currentUSDToDisplayRate`, plus the selected currency.
- **Settings**: the dashboard settings (`tokenSettings.minimumDashboardValue`, `tokenSettings.hideUnpriced`, `tokenSettings.hideDust`), the historical-backfill flag (`historicalPriceBackfill.isEnabled`) and the watchlist (`OverviewWatchlistCoinGeckoIDs`), with today's defaults, on today's `UserDefaults` keys, read and observed through the `DashboardSettingsClient`.
- **Prepared input**: a valuation input with the price ID and the override `PortfolioValuation` resolves for it. Both depend only on the override rows, the identity mappings and the asset.

## Projection

### P1: Content
A projection holds:
- **Holdings**: the active accounts' prepared inputs, categorized with the store's category rules (`PortfolioCategoryResolver.live`, which falls back to the defaults when the store has no category).
- **Polling candidates**: the active accounts' prepared inputs, categorized with the default rules, each carrying its sync-time `usdValue`. Unranked.
- **Position groups**: one `AllPositionsCardInfo` per active position, including a position with no token.
- **Asset index**: every asset by ID: symbol, name, legacy category, CoinGecko ID and logo URL, as stored (overrides are not applied).
- **Account index**: every account by ID: name, kind and whether it is active.
- **Overrides and mappings**: every `TokenPricingOverride` and `TokenIdentityMapping` row as its snapshot.
- **Historical book**: the recent-window USD book (P3).

### P2: Order and characterization
- Holdings and position groups equal `ActivePortfolioProjection(positions, categoryResolver:)` over every `Position` in fetch order, with the store's resolver: the same inputs in the same order, and the same cards.
- Polling candidates equal `ValuationInput.activeAccounts(tokens, categoryResolver: .defaults)` over every `PositionToken` in fetch order, which is what OverviewView ranks today.
- A token with no asset, or whose position or account is gone, is in neither list.
- Preparing changes no value: for any inputs, market, overrides and mappings, `PortfolioValuation(prepared:market:)` over the prepared inputs equals `PortfolioValuation(inputs:market:overrides:mappings:)`.

### P3: Historical book
- It equals `HistoricalMarketPricesFeature.prices(from:isBackfillEnabled:now:)` over the `HistoricalPricePoint` rows whose day is on or after `MarketPrices.closeWindowStart(now:)`, sorted by day then price ID, with the backfill flag and the build time `now`.
- It is USD only: non-USD rows are dropped, never converted. It takes no currency and no rate.
- With backfill disabled it is empty.

### P4: Inactive accounts
- An inactive account's positions and tokens appear in no list of P1 except the account index.

## Building

### B1: Triggers
The projection is rebuilt:
- once when the app launches;
- after a save that touches an entity the projector reads (B3), debounced by 300 ms, so a burst of saves builds once;
- when a dashboard setting or the backfill flag changes (a dashboard-setting change yields an equal projection, since no projection input reads those settings, so it stores nothing and revalues nothing more);
- at each UTC midnight, when `MarketPrices.closeWindowStart` moves, with no save needed. A close or a 24h fraction whose day leaves the window leaves the projection then.

It is **not** rebuilt on:
- a live price tick;
- a display-currency switch or a rate refresh, because no projection input depends on them;
- a save that touches only other entities (snapshots, `CurrencyConversionRatePoint`, sync bookkeeping that no read entity records);
- a navigation click;
- a watchlist change.

### B2: Off the main thread
- The projector is created on its own dispatch queue, like `PerformanceDataClient.makeFetcher`, so its model context never runs on the main thread.
- A Debug-only probe on the projector reports whether it executes on the main thread.

### B3: Read entities
`Account`, `Position`, `PositionToken`, `Asset`, `TokenPricingOverride`, `TokenIdentityMapping`, `PortfolioCategory`, `CategorySymbolRule`, `HistoricalPricePoint`.

### B4: Latest build wins
- A new build cancels a build in flight, so an older result never replaces a newer one.
- A build that throws leaves the current projection in place; before the first build that is no projection, and the next trigger retries.
- A build equal to the current projection is not stored and triggers no revaluation.

## Valuation

### V1: Triggers
Exactly one revaluation follows each of:
- a USD price update (`pricesReceived`, `onchainFallbackPricesReceived`);
- a stored projection change (B4);
- a display-rate change: a committed currency switch or a refreshed rate;
- a change of a dashboard setting or the watchlist.

A backfill-flag change revalues only through the projection change its rebuild stores, since the valuator never reads the flag.

A price tick never rebuilds the projection (B1). A non-USD price update changes nothing, as today.

### V2: Output
- **Headline**: `OverviewFeature.headline` over the holdings, the overrides and mappings, the live book with the live 24h fractions merged over the historical ones, and the display rate. It is stored with the currency it was valued in.
- **Polling IDs**: `OverviewFeature.pricePollingIDs` over the polling candidates, the overrides and mappings, the live book without live fractions plus the historical book, the dashboard settings and the watchlist. The same ranking as today: live value first, ties by first index, the holdings capped at 25, then the watchlist.
- Before the first build there is no projection and no valued output: nothing is revalued and nothing is polled.

### V3: Budget
- One revaluation on a Release build with the real store takes at most 16 ms, measured by the `PortfolioValuation` signpost.
- If it misses, revaluation runs in an off-main effect (its inputs are `Sendable` values) and the reducer stores only the result.

## Slice

### S1: Sidebar portfolio header and Overview top bar
- Each renders only from `StoreOf<PortfolioFeature>`: no `@Query`, `@AppStorage`, `Environment<AppState>` or `ValuationSources`, at any depth.
- For the same store, prices, rate and settings, each shows the same formatted strings as on master: total, 24h change and 24h percentage, in the display currency.
- Before the first build each shows "—" for the total, the change and the percentage. This launch transient is the one visible difference from master.
- A navigation click re-renders neither.

### S2: Polling
- OverviewView starts polling with the reducer's polling IDs, keyed by their set, and stops polling when the set is empty or the view disappears, as today.
- Exposure is unchanged.

## Timing

### T1: Signposts
- `PortfolioProjectionBuild` wraps each projector build; `PortfolioValuation` wraps each revaluation.
- In Debug, the debug server serves the most recent duration of each, in milliseconds, at `GET /state/portfolio/timings`. Before the first interval a duration is `null`.
