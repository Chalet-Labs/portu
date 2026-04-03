# AllAssetsFeature Behavioral Spec

## What

Migrate AllAssets views to a TCA child feature scoped from AppFeature. The reducer manages tab selection, search filtering, and grouping mode. Row aggregation logic is extracted as a testable pure function.

## Why

Phase 4.1 of TCA migration. Moves AllAssets UI state from scattered `@State` into a testable reducer with explicit actions. Establishes the child-feature pattern for remaining Phase 4 migrations.

## Scope

### Included
- AllAssetsView tab selection
- AssetsTab search text and grouping mode
- Row aggregation extracted as a testable pure function
- Child feature scoping from AppFeature

### Excluded
- SwiftData `@Query` stays in views (Phase 3 constraint)
- Sort order stays as view-local `@State` (Table-owned, `KeyPathComparator` not `Equatable`)
- PlatformsTab / NetworksTab aggregation (read-only display, no managed state)
- Asset detail navigation (Phase 4.2)
- CSV export stays in view (NSSavePanel is UI-only; CSV generation is testable as pure function)

## State

| Property | Type | Default | Description |
|---|---|---|---|
| selectedTab | AssetTab | .assets | Current tab (assets, nfts, platforms, networks) |
| searchText | String | "" | Filter text for asset search |
| grouping | AssetGrouping | .none | Row grouping mode (none, category, priceSource) |

## Types

```
enum AssetTab: String, CaseIterable, Equatable
    assets, nfts, platforms, networks

enum AssetGrouping: String, CaseIterable, Equatable
    none, category, priceSource
```

## Actions

### User Actions
- `tabSelected(AssetTab)` -- User taps tab picker
- `searchTextChanged(String)` -- User types in search field
- `groupingChanged(AssetGrouping)` -- User selects grouping from picker

### Internal Actions
None -- this is a pure-state feature with no effects.

## Behaviors

### B1: Tab Selection
- WHEN `tabSelected` is sent
- THEN `state.selectedTab` updates to the new tab
- AND no side effects run

### B2: Search Text
- WHEN `searchTextChanged` is sent
- THEN `state.searchText` updates to the new value
- AND no side effects run

### B3: Grouping Change
- WHEN `groupingChanged` is sent
- THEN `state.grouping` updates to the new value
- AND no side effects run

### B4: Asset Row Aggregation (Pure Function)
- GIVEN a list of PositionTokens and a price map [String: Decimal]
- WHEN aggregated into rows
- THEN tokens are grouped by Asset.id
- AND net amount = positive amounts - borrow amounts
- AND live prices used when coinGeckoId matches price map
- AND sync-time fallback price = weighted average from USD values
- AND rewards are excluded from aggregation
- AND value = netAmount * livePrice (or positiveUSD - borrowUSD for fallback)

### B5: Asset Row Search Filtering (Pure Function)
- GIVEN aggregated rows and a search text
- WHEN filtered
- THEN only rows matching symbol OR name (case-insensitive) are returned
- AND empty search text returns all rows

### B6: CSV Generation (Pure Function)
- GIVEN aggregated rows
- WHEN CSV is generated
- THEN output has header: Symbol,Name,Category,Net Amount,Price,Value
- AND one line per row with correct formatting

## Composition

AllAssetsFeature is scoped from AppFeature as a child reducer:

```
AppFeature.State
  ├── allAssets: AllAssetsFeature.State
  └── prices: [String: Decimal] (existing)
```

- AppFeature.Action includes `.allAssets(AllAssetsFeature.Action)`
- View reads `store.prices` from parent for row computation
- View reads `store.allAssets.*` for UI state

## Constraints

- SwiftData `@Query` remains in views -- the reducer does NOT manage query results
- Prices are NOT duplicated in child state -- views read from parent store
- Row aggregation is a standalone function, not a reducer concern
- No effects in this reducer -- all actions are synchronous state updates
