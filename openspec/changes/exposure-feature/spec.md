# ExposureFeature — TCA Migration Spec

## Scope

Migrate `ExposureView` from `@Environment(AppState.self)` + `@State` to TCA.

### In scope
- Child reducer `ExposureFeature` under `AppFeature`
- View toggle (`showByAsset`) as reducer state
- Pure functions for: category exposure, asset exposure, summary totals
- Reuse `TokenEntry` from AllAssetsFeature as input (same fields needed)

### Out of scope
- Derivatives (placeholder — "Coming soon")

---

## Behaviors

### B1: View mode toggle
- Segmented picker toggles between category view and asset view
- State change through reducer action

### B2: Category exposure aggregation
- Given token entries + live prices:
  - Groups by asset category
  - Sums spot assets (positive roles) and liabilities (borrow roles)
  - Excludes rewards
  - Returns only categories with non-zero values
  - Ordered by AssetCategory.allCases (stable ordering)
  - Each row has: name, spotAssets, liabilities, spotNet, netExposure

### B3: Asset exposure aggregation
- Given token entries + live prices:
  - Groups by asset ID
  - Sums spot assets and liabilities per asset
  - Returns sorted by spotNet descending
  - Each row has: symbol, category, spotAssets, liabilities, spotNet, netExposure

### B4: Summary totals
- Given category exposures:
  - totalSpot = sum of spotAssets across all categories
  - totalLiabilities = sum of liabilities across all categories
  - netExposure = sum of spotNet excluding stablecoin category

### B5: Token USD value resolution
- Pure function: given token amount, coinGeckoId, usdValue, and live prices
- Returns live price * amount when available, else fallback usdValue
- Shared logic across aggregation functions (not duplicated)
