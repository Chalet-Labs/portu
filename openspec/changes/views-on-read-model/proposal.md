# Views on the Read Model

## What

Every remaining dashboard screen renders from the portfolio read model (#123) instead
of querying and valuing the store in its own `body`. The views become thin renderers of
reducer state, and the per-view pipelines (`ValuationSources`, `OverviewCategorySource`,
the in-view `@Query`s, `ActivePortfolioProvider`, `HistoricalPricesProvider`) are deleted
once their last reader moves.

Issue: #124 (epic #116). Type: **Refactor**. Every rendered value stays as it is on
master after #122. The only differences are the launch transient from #123 ("—" until the
first build) and three timing points, all PR 1:

- the chart's month window moves at each chart rebuild (every sync's snapshot save and every
  UTC midnight), not at every render;
- the chart's "today" (the day converted at the live rate) moves at UTC midnight;
- the panels' recent-window closes move at UTC midnight, as the headline's have since #123,
  not at the next navigation click.

Panels follow a save after the 300 ms debounce and an off-main build (the headline has since
#123), and a watchlist edit shows once the settings echo returns; both settle on master's values.

It ships as three PRs:

1. **The rest of Overview** (this change's first part): summary cards, position tabs,
   top-assets donut, portfolio health, price watchlist and the value chart.
2. Exposure, All Assets (Assets, Platforms, Networks) and Performance's price inputs.
3. All Positions, Asset Detail, Accounts, Token Settings, then cleanup.

## Why

After #123 only the Sidebar header and the Overview top bar render from the read model.
Every other Overview panel still holds `@Query`s, `ValuationSources` (with its own
`@Query`s, `@AppStorage`s and `AppState`) and `OverviewCategorySource`, and values the
whole portfolio on the main thread in its `body`: on every price tick, every save and
every settings change. On #116 the Overview tick still shows two ~480 ms Microhangs after
#123, and navigating into Overview 761–876 ms. The value chart queries every
`PortfolioSnapshot` ever recorded, unpredicated, and filters to one month in its body.

## Decisions (PR 1)

Each is listed so it can be vetoed in review.

1. **The #144 seams stay the presentation functions.** `OverviewSummaryCardsFeature.cards`,
   `OverviewPositionProjection.tab`, `OverviewFeature.topAssets`, `watchlistRows`,
   `watchlistSuggestions` and `PortfolioHealthFeature.health` already take a
   `ValuationContext` and are spec'd against #122's fixtures. They keep their specs.
   What moves is who builds their context: `PortfolioValuator.compute`, once per
   revaluation, off the main thread, from the projection.
2. **Two input sets, each valued once per revaluation.** The holdings (active positions in
   fetch order, then their tokens) feed the headline, the cards and the tabs; the active
   tokens (every token in fetch order) feed polling, the watchlist, the donut and health.
   Those are today's inputs and orders, so labels that take a row's first token stay as
   they are. The context is memoized, so every seam over a set shares one valuation, and
   the tabs filter it (`PortfolioValuation.restricted`) instead of valuing their subset
   again.
3. **One category resolver.** The active tokens are categorized with the store's rules,
   not the defaults. Polling and the watchlist read no category, so their output is
   unchanged; the donut and health already used the store's rules.
4. **Live 24h fractions everywhere.** Each set is valued with the live fractions merged
   over the historical ones. Cards, donut, health and polling read no 24h figure, so their
   output is unchanged.
5. **All tabs and both donut modes per revaluation.** A tab or mode click re-renders from
   stored state with no round trip. The selection stays view `@State`: it is
   presentation, not data. Health's "show all" stays in `PortfolioHealthFeature.State`.
6. **Per-panel state.** `valued` keeps only the headline, its currency and the polling
   IDs. The panels' outputs live in a nested observable `overview` state, one field per
   panel plus the currency code, each written in place and only when it changed. A tick
   that leaves a panel's output equal doesn't re-render it, and a panel never re-renders
   because the headline moved.
7. **The whole value chart moves into the read model** (decided 2026-10-22 by the user,
   beyond the issue's "snapshot series"). A separate `PortfolioValueChartProjector`
   (its own `@ModelActor`, model context and creation queue, so the headline never waits
   behind it) builds the month of snapshots, the month of FX rate rows for every quote
   currency and the USD estimated segment. A failed snapshot or rate fetch keeps the chart
   already shown, or retries after 30 s when there is none, and the chart's dash carries its
   own error; a failed estimate fetch draws no estimate. Both are logged. The chart is
   converted to the display currency off the main thread on a new chart source, a currency or
   rate change, every UTC midnight and a reopened window, never on a price tick.
8. **The watchlist writes through the reducer.** The Add and Remove buttons send an action
   that persists through `DashboardSettingsClient` (a locked read-modify-write on today's
   key). UserDefaults stays the one source of truth: the settings stream's echo updates
   the state and revalues, as the `@AppStorage` write did.
9. **Before the first build** each panel shows "—" with the unavailable help, like the top
   bar. After a build with nothing to show, each panel shows its empty text as today.

## Scope (PR 1)

### In scope
- `PortfolioValuation.restricted` in PortuCore.
- Projection fields: active tokens, categories, position metadata, watchlist candidates.
- The value-chart projector, its triggers, its conversion and its signpost.
- The valuator's Overview outputs and the per-panel state.
- The watchlist actions and client methods.
- The six Overview views on the read model, and deleting the per-view Overview path
  (`ValuationSources+Overview`, `OverviewCategorySource`, `ValuationContext.activePortfolio`,
  `ValuationContext.restricted(to:)`, `OverviewPositionProjection.inputs(from:)`,
  `PortfolioValueChartEstimateFetcher`). `OverviewAssetCandidate.fromAssets` stays: the
  projector calls it, off the main actor.

### Out of scope
- PR 2 and PR 3 screens; `ValuationSources` itself stays until PR 3.
- Polling ownership (#101), deleting `AppState` (#125).

## Architecture (after PR 1)

```text
SwiftData store
  ├─ PortfolioProjector (@ModelActor)            build → PortfolioProjection
  └─ PortfolioValueChartProjector (@ModelActor)  build → PortfolioValueChartSource
        ▼
AppFeature
  ├─ prices, rate, currency                       (unchanged owners)
  └─ portfolio: PortfolioFeature.State
        projection?, settings, valued? (headline, currency, polling IDs)
        overview (per-panel fields)                ← PortfolioValuator, off main, per tick
        valueChartSource?, valueChart?             ← conversion, off main, on rate/currency/day
        ▼
SidebarPortfolioHeader, OverviewTopBar, OverviewSummaryCards, OverviewPositionTabs,
TopAssetsDonut, PortfolioHealthPanel, PriceWatchlist, PortfolioValueChart
```

## Risks

| Risk | Mitigation |
|---|---|
| More outputs per tick miss the off-main budget | Each input set valued once; tabs filter. Measured on Release with the real store (`valuationMs`). |
| The chart build's first-day `AssetSnapshot` fetch (≈12k rows, #97) delays the headline | Its own actor and queue; spec'd that a chart build held open doesn't delay a holdings build. |
| The chart window and "today" freeze between rebuilds | The chart rebuilds on every snapshot save and at each UTC midnight, and re-converts at each UTC midnight. Listed in the PR as the two timing-only differences. |
| A panel re-renders on every tick through a shared property | Per-panel fields written only when changed; `withObservationTracking` specs per panel. |
| A wrong input set wired to a panel goes unnoticed | The valuator oracle uses a projection whose holdings and active tokens differ in content and order. |
