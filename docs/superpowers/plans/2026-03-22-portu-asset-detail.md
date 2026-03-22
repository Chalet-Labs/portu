# Portu Asset Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Asset Detail drill-down with historical chart modes, holdings summary, per-network breakdown, and position-level context.

**Architecture:** Treat Asset Detail as a routed feature anchored on `Asset` identity, query current positions and historical snapshots separately, and keep chart mode switching in a view model that can combine live metadata with snapshot-derived time series. Use `navigationDestination(for: Asset.ID.self)` from the app shell so any future asset tap can land on the same screen.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Charts, SwiftData, PortuUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Skills to use:** @swift-architecture-skill, @swiftui-pro, @swiftdata-pro, @swift-testing-pro

**Dependencies:** Start after `docs/superpowers/plans/2026-03-22-portu-data-foundation.md`, `docs/superpowers/plans/2026-03-22-portu-overview-navigation.md`, and `docs/superpowers/plans/2026-03-22-portu-all-assets.md`.

---

## File Map

```
Portu/
├── Sources/Portu/
│   ├── App/ContentView.swift
│   └── Features/
│       └── AssetDetail/
│           ├── AssetDetailView.swift                  # new
│           ├── AssetDetailViewModel.swift             # new
│           ├── Models/
│           │   ├── AssetChartMode.swift               # new
│           │   ├── AssetComparison.swift              # new
│           │   ├── AssetDetailPositionRow.swift       # new
│           │   └── AssetHoldingSummaryRow.swift       # new
│           └── Sections/
│               ├── AssetMetadataSidebar.swift         # new
│               ├── AssetPositionsTable.swift          # new
│               ├── AssetPriceChart.swift              # new
│               └── AssetSummarySection.swift          # new
└── Tests/PortuTests/
    ├── AssetDetailChartTests.swift                    # new
    └── AssetDetailViewModelTests.swift                # new
```

---

### Task 1: Build the asset-detail data projection layer

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/AssetDetailViewModel.swift`
- Create: `Sources/Portu/Features/AssetDetail/Models/AssetChartMode.swift`
- Create: `Sources/Portu/Features/AssetDetail/Models/AssetComparison.swift`
- Create: `Sources/Portu/Features/AssetDetail/Models/AssetHoldingSummaryRow.swift`
- Create: `Sources/Portu/Features/AssetDetail/Models/AssetDetailPositionRow.swift`
- Test: `Tests/PortuTests/AssetDetailViewModelTests.swift`

- [ ] **Step 1: Write failing tests for net value, net amount, and chain summaries**

```swift
@Test func assetDetailUsesNetUsdValueForValueMode() throws {
    let point = try #require(AssetDetailViewModel.fixture().valueSeries.first)
    #expect(point.value == -500)
}

@Test func chainSummariesUsePositionChainNotAssetUpsertChain() throws {
    let row = try #require(AssetDetailViewModel.fixture().networkRows.first)
    #expect(row.networkName == "Arbitrum")
}
```

- [ ] **Step 2: Run the asset-detail tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AssetDetailViewModelTests test`

Expected: FAIL because the feature projection layer does not exist.

- [ ] **Step 3: Implement the asset-detail view model**

```swift
@MainActor
@Observable
final class AssetDetailViewModel {
    var selectedMode: AssetChartMode = .price
    var selectedComparison: AssetComparison?
    var valueSeries: [PerformancePoint] = []
    var amountSeries: [PerformancePoint] = []
    var networkRows: [AssetHoldingSummaryRow] = []
    var positionRows: [AssetDetailPositionRow] = []
}
```

- [ ] **Step 4: Re-run the asset-detail tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AssetDetailViewModelTests test`

Expected: PASS with network grouping and snapshot-derived series covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/AssetDetailViewModel.swift Sources/Portu/Features/AssetDetail/Models Tests/PortuTests/AssetDetailViewModelTests.swift
git commit -m "feat: add asset detail projection models"
```

---

### Task 2: Implement the chart modes and comparison overlays

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/Sections/AssetPriceChart.swift`
- Test: `Tests/PortuTests/AssetDetailChartTests.swift`

- [ ] **Step 1: Write failing tests for chart-mode switching**

```swift
@Test func borrowOnlyAssetsDisplayDebtLabelInValueMode() throws {
    let viewModel = AssetDetailViewModel.fixtureBorrowOnly()
    #expect(viewModel.valueSummaryLabel == "Debt: $500.00")
}
```

- [ ] **Step 2: Run the chart tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AssetDetailChartTests test`

Expected: FAIL because the chart component and mode labels are missing.

- [ ] **Step 3: Implement the chart component**

```swift
struct AssetPriceChart: View {
    let mode: AssetChartMode
    let priceSeries: [PerformancePoint]
    let valueSeries: [PerformancePoint]
    let amountSeries: [PerformancePoint]
}
```

- [ ] **Step 4: Re-run the chart tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AssetDetailChartTests test`

Expected: PASS with price, value, and amount modes covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/Sections/AssetPriceChart.swift Tests/PortuTests/AssetDetailChartTests.swift
git commit -m "feat: add asset detail chart modes"
```

---

### Task 3: Implement the summary, position table, and metadata sidebar

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/Sections/AssetSummarySection.swift`
- Create: `Sources/Portu/Features/AssetDetail/Sections/AssetPositionsTable.swift`
- Create: `Sources/Portu/Features/AssetDetail/Sections/AssetMetadataSidebar.swift`
- Create: `Sources/Portu/Features/AssetDetail/AssetDetailView.swift`

- [ ] **Step 1: Add a failing smoke test for the asset detail surface**

```swift
@Test func assetDetailDefaultsToPriceMode() {
    #expect(AssetDetailViewModel().selectedMode == .price)
}
```

- [ ] **Step 2: Run the asset-detail tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AssetDetailViewModelTests test`

Expected: FAIL because the feature UI is missing.

- [ ] **Step 3: Implement the detail workspace**

```swift
struct AssetDetailView: View {
    let assetID: Asset.ID
    var body: some View {
        HSplitView {
            VStack { AssetPriceChart(...); AssetSummarySection(...); AssetPositionsTable(...) }
            AssetMetadataSidebar(...)
        }
    }
}
```

- [ ] **Step 4: Re-run the app build**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED with the new feature compiling cleanly.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/Sections/AssetSummarySection.swift Sources/Portu/Features/AssetDetail/Sections/AssetPositionsTable.swift Sources/Portu/Features/AssetDetail/Sections/AssetMetadataSidebar.swift Sources/Portu/Features/AssetDetail/AssetDetailView.swift
git commit -m "feat: add asset detail workspace"
```

---

### Task 4: Wire `navigationDestination(for: Asset.ID.self)` and finish end-to-end verification

**Files:**
- Modify: `Sources/Portu/App/ContentView.swift`
- Modify: `Sources/Portu/Features/AllAssets/Tabs/AssetsTabView.swift`
- Modify: `Sources/Portu/Features/Overview/Sections/OverviewInspector.swift`

- [ ] **Step 1: Add a failing test for asset navigation**

```swift
@Test func contentViewDeclaresAssetDestinationType() {
    #expect(ContentView.assetDestinationTypeName == "Asset.ID")
}
```

- [ ] **Step 2: Run the app tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: FAIL because the app shell does not yet declare `navigationDestination(for: Asset.ID.self)`.

- [ ] **Step 3: Wire the shared asset-detail destination**

```swift
.navigationDestination(for: Asset.ID.self) { assetID in
    AssetDetailView(assetID: assetID)
}
```


- [ ] **Step 4: Re-run the full app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with All Assets and Overview drill-ins landing on the shared asset-detail screen.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/App/ContentView.swift Sources/Portu/Features/AllAssets/Tabs/AssetsTabView.swift Sources/Portu/Features/Overview/Sections/OverviewInspector.swift
git commit -m "feat: wire shared asset detail navigation"
```
