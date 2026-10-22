# Portfolio Read Model

## What

An off-main projector builds the active portfolio once per data change, and a
portfolio child reducer in `AppFeature` revalues it with #122's `PortfolioValuation`
on every price tick. The Sidebar portfolio header and the Overview top bar render
only from that reducer state. They are the vertical slice that proves the read
model; every other screen moves in #124.

Issue: #123 (epic #116). Type: **Refactor**. Every rendered value and every
existing reducer transition stays as it is on master after #122 (`50e03292`).

## Why

The slice readers still re-run on every save and the header on every navigation
click: each holds `ValuationSources`, a `DynamicProperty` with
`@Environment(AppState.self)`, two `@Query`s and three `@AppStorage`s. The
projection `ActivePortfolioProvider` publishes is built on the main actor, inside a
SwiftUI body, with a model walk per save. OverviewView values the whole portfolio a
second time in its body to rank the polling IDs.

## Decisions

Made on 2026-10-21 while writing this change; each is listed so it can be vetoed in
review.

1. **Feature folder** `Sources/Portu/Features/Portfolio/`: `PortfolioProjection`,
   `PortfolioProjector` (the `@ModelActor`), `PortfolioProjectorClient`,
   `PortfolioFeature` (the child reducer) and `PortfolioValuator`.
2. **Prices stay in `AppFeature.State`.** The USD live book, the 24h fractions and
   the display rate keep their owner (`livePricesUSD`, `priceChanges24h`,
   `currentUSDToDisplayRate`), because `AppState`, the debug server and every
   unmigrated screen read them. `AppFeature` revalues the portfolio child where those
   inputs change. No price is copied into the child.
3. **One revaluation computes the whole valued output**: the headline in the display
   currency and the polling IDs. Revaluing goes through a `PortfolioValuator`
   dependency, so tests count revaluations and the fallback of the per-tick budget
   (an off-main effect) has a seam. The 16 ms budget covers the whole call (two
   valuation passes: headline and polling).
4. **Settings come from a `DashboardSettingsClient`, on today's keys.** The child holds
   the dashboard settings (`tokenSettings.*`), the historical-backfill flag and the
   watchlist as plain `Equatable` state, loaded and observed through a dependency client
   over `UserDefaults` (`didChangeNotification`, filtered by value). UserDefaults stays
   the one source of truth. Decided 2026-10-22 instead of the issue's
   `@Shared(.appStorage)`: every key has a period, and swift-sharing reports an issue
   for a dotted app-storage key on subscribe (`AppStorageKey.swift:458`), which Swift
   Testing records as a failure in every test that builds `AppFeature.State`.
   Migrating the keys would be a user-data migration inside a Refactor PR. A change to
   any setting revalues; a change to the dashboard settings or the backfill flag also
   rebuilds the projection. The watchlist only feeds the polling IDs.
5. **The polling IDs move into the reducer, polling ownership does not.** OverviewView
   starts and stops polling with the reducer's polling IDs instead of ranking its own
   `@Query<PositionToken>`. Exposure keeps its own IDs. #101 moves ownership.
6. **Two input lists.** The holdings follow today's headline input: active positions in
   fetch order, then each position's tokens, categorized with the user's category
   rules. The polling candidates follow today's polling input: every token in fetch
   order, categorized with the default rules. Ranking breaks ties by first index, so
   keeping each order keeps the ranking.
7. **Holdings are prepared: mapped and overridden.** Each input is stored with the
   price ID and the override `PortfolioValuation` resolves for it today. Both depend
   only on the store (the override, the identity mappings, the asset), never on a price.
   PortuCore gains `PreparedValuationInput` and `PortfolioValuation(prepared:market:)`.
   The existing initializer prepares and then calls it, so there is still one policy,
   and the per-tick valuation skips the override and mapping lookups.
8. **`ActivePortfolioProvider` stays for All Positions only.** The header and the top
   bar stop reading it, and it moves from the window root to wrap only
   `AllPositionsView`, so its main-thread walk per save runs only while All Positions
   is shown. #124 moves All Positions and then deletes the provider.
9. **`HistoricalPricesProvider` stays** for the unmigrated screens. The projection
   builds its own USD book from the same rows with the same function
   (`HistoricalMarketPricesFeature.prices`). The provider re-derives its window when
   the dashboard is rebuilt; the projection is rebuilt at each UTC midnight instead, the
   moment the window start (`MarketPrices.closeWindowStart`) moves, so an expired close
   or fraction never outlives its day without a save. #124 removes the environment book.
10. **Before the first build** the reducer has no projection: the slice shows "—" for
    the total, the change and the percentage, and nothing is polled. A first build
    that fails leaves that state; the next trigger retries. Decided 2026-10-22; this is
    the one visible difference from master (a launch transient) and the PR lists it.
11. **Signposts** use one `OSSignposter` (subsystem `com.portu.app`, category
    `PortfolioReadModel`) with intervals `PortfolioProjectionBuild` and
    `PortfolioValuation`, read with xctrace on Release. In Debug, the debug server also
    serves the most recent duration of each at `GET /state/portfolio/timings`.

## Scope

### In scope

- `PreparedValuationInput` and `PortfolioValuation(prepared:market:)` in PortuCore.
- The projection value type, the projector, the projector client and its save,
  settings and UTC-midnight triggers.
- The `DashboardSettingsClient` over today's `UserDefaults` keys.
- The portfolio child reducer, its revaluation triggers and its polling-ID output.
- The Sidebar portfolio header and the Overview top bar rendering from reducer state.
- OverviewView polling from the reducer's IDs.
- `ActivePortfolioProvider` moved from the window root to wrap only All Positions.
- Signposts and the debug route.

### Out of scope

- Every other screen, including All Positions, the summary cards and the position
  tabs (#124).
- Polling ownership and sync-time ranking (#101).
- Deleting `AppState` (#125).
- Removing `ActivePortfolioProvider`, `HistoricalPricesProvider` and `ValuationSources`
  (#124 once their last reader moves).

## Architecture

```text
SwiftData store
  └─ PortfolioProjector (@ModelActor, created on its own dispatch queue)
        │  build(PortfolioProjectionRequest) -> PortfolioProjection
        ▼
PortfolioProjectorClient (dependency)
        ▼
AppFeature
  ├─ livePricesUSD, priceChanges24h, currentUSDToDisplayRate   (unchanged owners)
  └─ portfolio: PortfolioFeature.State
        projection?, settings (DashboardSettingsClient), valued?
        valued = headline + currency + pricePollingIDs, by AppFeature via PortfolioValuator
        ▼
SidebarPortfolioHeader, OverviewTopBar   (StoreOf<PortfolioFeature>)
OverviewView .task(id:)                  (the reducer's polling IDs)
```

## Risks

| Risk | Mitigation |
|---|---|
| Valuation per tick misses 16 ms on the main actor | Measured on a Release build with the real store via the `PortfolioValuation` signpost. The named fallback is an off-main effect behind `PortfolioValuator`. |
| The projection's historical window freezes `now` between rebuilds | The child rebuilds at each UTC midnight, when the window start moves, besides every relevant save. |
| Two historical books (projection and environment) disagree | Both come from `HistoricalMarketPricesFeature.prices` over the same predicate; #124 deletes the environment one. Within a day they can differ only in `now`, which the window ignores. |
| A defaults write outside the reducer arrives with no action | The settings client streams `didChangeNotification`, filtered to a change of value, and the child sends `settingsChanged`. |
| Exhaustive `AppFeature` tests start seeing portfolio state changes | Before the first build there is no projection, so a price tick or a rate change revalues nothing and the existing tests see no new state. |
| Preparing inputs changes a value | `PortfolioValuation(inputs:…)` becomes "prepare, then value", so every existing valuation spec runs through the prepared path, and a spec pins prepared == unprepared over the 18-token fixture. |
