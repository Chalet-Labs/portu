# AssetDetailFeature — TCA Migration Spec

## Scope

Migrate `AssetDetailView`, `AssetPriceChart`, `AssetHoldingsSummary`, and `AssetPositionsTable`
from `@Environment(AppState.self)` + `@State` to TCA. `AssetMetadataSidebar` is a pure view
(takes `Asset` directly) and needs no migration.

### In scope
- Child reducer `AssetDetailFeature` under `AppFeature`
- Chart mode / time range as reducer state (replacing `@State`)
- Pure functions for: position row aggregation, holdings summary computation, snapshot aggregation
- Lightweight input structs that decouple from SwiftData models
- Views read prices from parent store, @Query stays in views

### Out of scope
- Navigation changes (NavigationStack + `.navigationDestination(for: UUID.self)` stays as-is)
- CoinGecko historical price API (priceChart stays placeholder for `.price` mode)
- AssetMetadataSidebar (already pure, no AppState dependency)

---

## Behaviors

### B1: Chart mode selection
- Picker sets chart mode to `.price`, `.dollarValue`, or `.amount`
- State change through reducer action, not @State

### B2: Time range selection
- Picker sets time range to `.oneWeek`, `.oneMonth`, `.threeMonths`, or `.oneYear`
- State change through reducer action, not @State

### B3: Position row aggregation
- Given a list of token entries for a specific asset + live prices:
  - Computes amount, usdBalance per token (using live price if available, else sync-time value)
  - Returns rows sorted by usdBalance descending
  - Includes account name, platform, context (position type), network
- Rewards are included (unlike AllAssets where they're excluded)
- Borrows show negative amounts

### B4: Holdings summary computation
- Given token entries for a specific asset + live prices:
  - `totalAmount`: sum of positive - borrow amounts
  - `totalValue`: totalAmount * livePrice when available, else sum of usdValues
  - `accountCount`: distinct accounts holding this asset
  - `byChain`: chain name → (share %, value) sorted by value descending
- Only positive-role tokens contribute to byChain breakdown

### B5: Snapshot aggregation for charts
- Given asset snapshots + time range:
  - Filters to snapshots for the target asset within the time range
  - Aggregates by day (sum across accounts): grossUSD, borrowUSD, grossAmount, borrowAmount
  - Returns sorted by date ascending
- Used by both value chart (netUSD = gross - borrow) and amount chart (netAmount)

### B6: Header price display
- Given asset's coinGeckoId + live prices + 24h changes:
  - Returns current price + 24h change percentage
  - Returns nil when asset has no coinGeckoId or no live price
- Pure function, testable without SwiftData
