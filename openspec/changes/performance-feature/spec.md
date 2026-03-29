# PerformanceFeature — TCA Migration Spec

## Scope

Migrate `PerformanceView` and its child chart views from `@State` to TCA.
No `@Environment(AppState.self)` to replace — only SwiftData `@Query`.

### In scope
- Child reducer `PerformanceFeature` under `AppFeature`
- State: selectedAccountId, selectedRange, chartMode, disabledCategories, showCumulative
- Pure functions for: lastPerDay dedup, PnL bar computation, category change breakdown
- Enums: `PerformanceChartMode`, `PerformanceTimeRange` (distinct from AssetDetail's)

### Out of scope
- Custom date range picker (placeholder — uses 1M default)
- Asset prices panel in PerformanceBottomPanel (TODO placeholder)

---

## Behaviors

### B1: Account filter selection
- Picker sets selectedAccountId (nil = all accounts)

### B2: Time range selection
- Segmented picker sets time range

### B3: Chart mode selection
- Segmented picker sets chart mode (value/assets/pnl)

### B4: Category toggle (assets chart)
- Toggling a category adds/removes it from disabledCategories set

### B5: Cumulative toggle (PnL chart)
- Toggle shows/hides cumulative line on PnL chart

### B6: Last-per-day deduplication
- Given `[(Date, Decimal)]` values:
  - Keeps only the last value for each calendar day
  - Returns sorted by date ascending

### B7: PnL bar computation
- Given daily values (already deduped):
  - Computes daily PnL as difference between consecutive days
  - Computes running cumulative PnL
  - Returns empty if fewer than 2 days

### B8: Category change breakdown
- Given snapshot entries, accountId filter, startDate:
  - Compares first day vs last day USD values per category
  - Returns: category name, start value, end value, percent change
  - Omits categories with zero values on both days
  - Follows AssetCategory.allCases ordering
