# PortfolioHealthFeature — Behavioral Spec

## Scope

New feature: portfolio concentration risk and diversification metrics.
Displayed in the Overview inspector panel alongside TopAssetsDonut and PriceWatchlist.

### In scope
- Child reducer `PortfolioHealthFeature` under `AppFeature`
- Pure functions for: asset weight computation, concentration risk detection, diversification metrics, risk classification
- Reuses `TokenEntry` from AllAssetsFeature (same input shape)
- New output structs: `AssetWeight`, `ConcentrationRisk`, `DiversificationMetrics`, `RiskLevel`
- View: `PortfolioHealthPanel` in Overview inspector

### Out of scope
- Persisting health history or alerts
- Custom threshold configuration UI (uses fixed default for now)
- Notifications or push alerts

---

## Types

### AssetWeight
- `symbol: String` — asset symbol (e.g. "BTC")
- `name: String` — asset name (e.g. "Bitcoin")
- `usdValue: Decimal` — total USD value across all positions
- `percentage: Decimal` — weight as fraction of total portfolio (0.0–1.0)

### ConcentrationRisk
- `symbol: String`
- `name: String`
- `percentage: Decimal` — the asset's weight
- `threshold: Decimal` — the threshold it exceeds

### DiversificationMetrics
- `assetCount: Int` — number of distinct assets with value > 0
- `chainCount: Int` — number of distinct chains
- `stablecoinRatio: Decimal` — fraction of portfolio in stablecoins (0.0–1.0)
- `herfindahlIndex: Decimal` — HHI: sum of squared asset weights (0.0–1.0)

### RiskLevel
Enum: `.low`, `.medium`, `.high`

---

## Behaviors

### B1: Asset weight computation
`computeAssetWeights(tokens:prices:) -> [AssetWeight]`

- Groups tokens by asset identity (symbol + name pair)
- Resolves USD value per token: prefers live price (`amount × prices[coinGeckoId]`) when available, falls back to `usdValue`
- Sums USD values per asset
- Computes percentage as `assetValue / totalPortfolioValue`
- Returns sorted descending by percentage
- Returns empty array when no tokens have value

### B2: Concentration risk detection
`computeConcentrationRisks(weights:threshold:) -> [ConcentrationRisk]`

- Returns all `AssetWeight` entries where `percentage >= threshold`
- Preserves descending sort order from weights input
- Returns empty array when no asset exceeds threshold
- Default threshold: 0.25 (25%)

### B3: Diversification metrics
`computeDiversificationMetrics(tokens:weights:chainCount:prices:) -> DiversificationMetrics`

- `assetCount`: count of weights
- `chainCount`: passed in by caller (distinct chains from positions)
- `stablecoinRatio`: sum of resolved stablecoin USD values / total portfolio value
  - Stablecoin identified by `category == .stablecoin` and `role.isPositive`
  - Uses `resolveValue(token:prices:)` so numerator matches the denominator's value source
- `herfindahlIndex`: sum of `percentage²` across all weights
- When portfolio is empty (total = 0): assetCount = 0, chainCount = 0, stablecoinRatio = 0, herfindahlIndex = 0

### B4: Risk level classification
`classifyRiskLevel(metrics:) -> RiskLevel`

- `.high` if HHI > 0.5 (one asset dominates >70%)
- `.medium` if HHI > 0.25
- `.low` otherwise
- Edge: empty portfolio (HHI = 0) → `.low`

### B5: Reducer state
- `showAllAssets: Bool = false` — toggle between top 5 and full list

### B6: Reducer actions
- `showAllAssetsToggled` — flips `showAllAssets`
