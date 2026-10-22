# Views on the Read Model Behavioral Spec (PR 1: Overview)

Terms as in `openspec/changes/portfolio-read-model/spec.md`. **Today's seam** means the
#144 presentation function over the context the view built in its body on master.

## Overview outputs

### O1: Content
One revaluation produces, besides the headline and the polling IDs:
- **Summary cards**: `OverviewSummaryCardsFeature.cards` over the holdings, with the
  projection's categories for the majors row label.
- **Position tabs**: `OverviewPositionProjection.tab` for each of the four tabs over the
  holdings and the projection's position metadata.
- **Top assets**: `OverviewFeature.topAssets` for both modes over the active tokens.
- **Health**: `PortfolioHealthFeature.health` over the active tokens.
- **Watchlist rows**: `OverviewFeature.watchlistRows` over the active tokens, the
  projection's watchlist candidates and the watchlist.
- **Currency code**: the display currency the outputs were converted with.

### O2: Equality
For the same store, prices, rate and settings, each output equals today's seam over
today's context: the cards, donut and health without live 24h fractions, the tabs and
watchlist with them. Each input set is valued once and shared; a tab filters the shared
valuation by the tokens it admits, which equals valuing them alone.

### O3: Observation
- Each output is its own observed field, written only when it changed.
- A revaluation whose headline is equal notifies no reader of the headline.
- A change to the live 24h fractions alone notifies the tabs, the watchlist and the
  headline readers, and not the cards, the donut, health or the chart.
- A navigation click, and a failed rebuild while values show, notify no panel.

### O4: Before the first build
Each panel shows "—" with the unavailable help, never its empty text. After a build with
nothing to show, each panel shows today's empty text. Watchlist suggestions are empty
until the first build.

## Value chart

### C1: Source
The chart source holds, as values:
- every `PortfolioSnapshot` from `ChartTimeRange.oneMonth.startDate(at: now)` on, sorted by
  timestamp: ID, timestamp, USD total, partial flag;
- every `CurrencyConversionRatePoint` from that start's UTC day on, for every quote
  currency, sorted by day;
- the USD estimated segment: `PortfolioValueChartFeature.estimatedPoints` over the estimate
  source and the USD price rows in `[chartStartDay, firstRealSnapshotDate)`, sorted by day.
  With backfill off, neither the source nor the prices are fetched and the segment is empty.

It equals what the chart's queries, month filter and estimate task produced on master.

### C2: Build
- Its own `@ModelActor` (`PortfolioValueChartProjector`), created on its own dispatch
  queue; a chart build held open doesn't delay a holdings build.
- Triggers: the dashboard task (after the save subscription is live); a save touching
  `PortfolioSnapshot`, `CurrencyConversionRatePoint`, `AssetSnapshot`,
  `HistoricalPricePoint`, `TokenPricingOverride` or `Asset`, debounced by 300 ms; a
  backfill-flag change; each UTC midnight. The latest build wins.
- It never throws. A failed fetch yields an empty series or no estimate.
- An equal source is not stored.

### C3: Conversion
- Through `CurrencyConversionContext`: the live rate for today's UTC day, the historical
  row for earlier days, the live rate where a row is missing.
- Converted off the main thread on a stored source change, a committed currency switch, a
  refreshed rate, each UTC midnight, and the dashboard task with a kept source. Never on a
  price tick. An equal result is not stored.

### C4: Rendering
"—" before the first source; "No Data" when the month has no snapshot; the dashed segment
and its caption only when the estimate is non-empty.

## Watchlist

### W1: Writes
- Add and Remove persist through `DashboardSettingsClient` with a locked
  read-modify-write on `OverviewWatchlistCoinGeckoIDs`. The reducer state follows the
  settings stream, so two quick edits both persist and the state never reverts.
- Suggestions read the reducer's watchlist and the projection's candidates.

## Structure

### S1: Views
`OverviewSummaryCards`, `OverviewPositionTabs`, `TopAssetsDonut`, `PortfolioHealthPanel`,
`PriceWatchlist` and `PortfolioValueChart` hold a store and no `@Query`, `@AppStorage`,
`Environment`, `ValuationSources`, `OverviewCategorySource` or model context, at any
depth.
