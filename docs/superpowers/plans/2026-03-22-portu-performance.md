# Portu Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Performance workspace with Value, Assets, and PnL modes backed by the three snapshot tiers from the data-foundation plan.

**Architecture:** Query snapshots directly from SwiftData, keep chart-mode-specific transformations in a feature-local view model, and treat PnL as a derived presentation over the same snapshot series rather than a separate persistence layer. Separate value-series projection from chart rendering so account-filtering, category chips, and date-range logic stay testable.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Charts, SwiftData, PortuUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Skills to use:** @swift-architecture-skill, @swiftui-pro, @swiftdata-pro, @swift-testing-pro

**Dependencies:** Start after `docs/superpowers/plans/2026-03-22-portu-data-foundation.md` and `docs/superpowers/plans/2026-03-22-portu-overview-navigation.md`.

---

## File Map

```
Portu/
├── Sources/Portu/
│   ├── App/ContentView.swift
│   └── Features/
│       └── Performance/
│           ├── PerformanceView.swift                  # new
│           ├── PerformanceViewModel.swift             # new
│           ├── Models/
│           │   ├── PerformanceChartMode.swift         # new
│           │   ├── PerformancePoint.swift             # new
│           │   ├── PerformanceRange.swift             # new
│           │   └── PnLBarPoint.swift                  # new
│           └── Sections/
│               ├── AssetCategoriesPanel.swift         # new
│               ├── AssetPricesPanel.swift             # new
│               ├── PerformanceChartSection.swift      # new
│               └── PerformanceControls.swift          # new
└── Tests/PortuTests/
    ├── PerformancePnLTests.swift                      # new
    └── PerformanceViewModelTests.swift                # new
```

---

### Task 1: Build the snapshot query and range-selection layer

**Files:**
- Create: `Sources/Portu/Features/Performance/PerformanceViewModel.swift`
- Create: `Sources/Portu/Features/Performance/Models/PerformanceChartMode.swift`
- Create: `Sources/Portu/Features/Performance/Models/PerformancePoint.swift`
- Create: `Sources/Portu/Features/Performance/Models/PerformanceRange.swift`
- Test: `Tests/PortuTests/PerformanceViewModelTests.swift`

- [ ] **Step 1: Write failing tests for account-filtered value series and category stacking**

```swift
@Test func valueModeUsesAccountSnapshotsWhenAccountIsSelected() throws {
    let viewModel = PerformanceViewModel.fixture(accountFilter: .account(UUID()))
    #expect(viewModel.valuePoints.allSatisfy(\.usesAccountSnapshot))
}

@Test func assetModeStacksGrossUsdByCategory() throws {
    let category = try #require(PerformanceViewModel.fixture().assetStacks["major"]?.first)
    #expect(category.value > 0)
}
```

- [ ] **Step 2: Run the view-model tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/PerformanceViewModelTests test`

Expected: FAIL because the feature models and snapshot projection code are missing.

- [ ] **Step 3: Implement the feature-local snapshot projection**

```swift
@MainActor
@Observable
final class PerformanceViewModel {
    var selectedMode: PerformanceChartMode = .value
    var selectedRange: PerformanceRange = .oneMonth
    var selectedAccountID: UUID?
    var enabledCategories: Set<AssetCategory> = Set(AssetCategory.allCases)
}
```

- [ ] **Step 4: Re-run the view-model tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/PerformanceViewModelTests test`

Expected: PASS with value-mode and asset-mode data shaping covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Performance/PerformanceViewModel.swift Sources/Portu/Features/Performance/Models Tests/PortuTests/PerformanceViewModelTests.swift
git commit -m "feat: add performance snapshot projection models"
```

---

### Task 2: Implement Value and Assets chart modes

**Files:**
- Create: `Sources/Portu/Features/Performance/PerformanceView.swift`
- Create: `Sources/Portu/Features/Performance/Sections/PerformanceChartSection.swift`
- Create: `Sources/Portu/Features/Performance/Sections/PerformanceControls.swift`
- Modify: `Sources/Portu/App/ContentView.swift`

- [ ] **Step 1: Add a failing smoke test for mode switching**

```swift
@Test func performanceChartModeDefaultsToValue() {
    #expect(PerformanceViewModel().selectedMode == .value)
}
```

- [ ] **Step 2: Run the Performance tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/PerformanceViewModelTests test`

Expected: FAIL because the chart container and controls are missing.

- [ ] **Step 3: Implement the chart surface and controls**

```swift
struct PerformanceView: View {
    var body: some View {
        VStack(spacing: 20) {
            PerformanceControls(...)
            PerformanceChartSection(...)
        }
        .navigationTitle("Performance")
    }
}
```

- [ ] **Step 4: Re-run the view-model tests and build the app**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED with `.performance` routed to the new feature.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Performance/PerformanceView.swift Sources/Portu/Features/Performance/Sections/PerformanceChartSection.swift Sources/Portu/Features/Performance/Sections/PerformanceControls.swift Sources/Portu/App/ContentView.swift
git commit -m "feat: add performance value and assets charts"
```

---

### Task 3: Add PnL mode and the bottom analysis panels

**Files:**
- Create: `Sources/Portu/Features/Performance/Models/PnLBarPoint.swift`
- Create: `Sources/Portu/Features/Performance/Sections/AssetCategoriesPanel.swift`
- Create: `Sources/Portu/Features/Performance/Sections/AssetPricesPanel.swift`
- Test: `Tests/PortuTests/PerformancePnLTests.swift`

- [ ] **Step 1: Write failing tests for daily PnL and category-change math**

```swift
@Test func pnlUsesSnapshotDeltaBetweenDays() throws {
    let bars = PerformanceViewModel.fixture().pnlBars
    #expect(bars[1].value == 250)
}

@Test func categoryPanelUsesPeriodStartAndEndValues() throws {
    let row = try #require(PerformanceViewModel.fixture().categorySummaryRows.first)
    #expect(row.changePercent != 0)
}
```

- [ ] **Step 2: Run the PnL tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/PerformancePnLTests test`

Expected: FAIL because the PnL and bottom-panel projections do not exist.

- [ ] **Step 3: Implement PnL and bottom-panel projections**

```swift
struct PnLBarPoint: Identifiable {
    let id: Date
    let date: Date
    let value: Decimal
    let cumulativeValue: Decimal
}
```

- [ ] **Step 4: Re-run the PnL tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/PerformancePnLTests test`

Expected: PASS with daily deltas and start-vs-end category comparisons covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Performance/Models/PnLBarPoint.swift Sources/Portu/Features/Performance/Sections/AssetCategoriesPanel.swift Sources/Portu/Features/Performance/Sections/AssetPricesPanel.swift Tests/PortuTests/PerformancePnLTests.swift
git commit -m "feat: add performance pnl and analysis panels"
```

---

### Task 4: Finish account filters, category chips, and end-to-end verification

**Files:**
- Modify: `Sources/Portu/Features/Performance/PerformanceView.swift`
- Modify: `Sources/Portu/Features/Performance/PerformanceViewModel.swift`
- Modify: `Sources/Portu/Features/Performance/Sections/PerformanceControls.swift`

- [ ] **Step 1: Add a failing test for category-chip filtering**

```swift
@Test func disablingCategoryRemovesItsAreaSeries() throws {
    let viewModel = PerformanceViewModel.fixture()
    viewModel.enabledCategories.remove(.stablecoin)
    #expect(viewModel.assetStacks[.stablecoin] == nil)
}
```

- [ ] **Step 2: Run the Performance tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/PerformanceViewModelTests test`

Expected: FAIL because the final filter interaction is incomplete.

- [ ] **Step 3: Implement the remaining controls and partial-data warnings**

```swift
if currentSeriesContainsPartialSnapshots {
    SyncStatusBadge(status: .completedWithErrors(failedAccounts: partialAccountNames))
}
```

- [ ] **Step 4: Re-run the full app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with all three chart modes and the panel stack working together.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Performance/PerformanceView.swift Sources/Portu/Features/Performance/PerformanceViewModel.swift Sources/Portu/Features/Performance/Sections/PerformanceControls.swift
git commit -m "feat: finish performance filters and warnings"
```

