# Portu Overview And Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the scaffolding sidebar and portfolio screen with the production navigation shell and Overview dashboard that validates the Phase 1 foundation end-to-end.

**Architecture:** Keep routing in the app target with `NavigationSplitView`, use `@Query` for persisted data access, and concentrate multi-model aggregation in small feature-local helpers or `@Observable` view models rather than a global store. Treat Overview as the reference screen for snapshot queries, price fallback rules, and sync status presentation.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Charts, SwiftData, PortuUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Skills to use:** @swift-architecture-skill, @swiftui-pro, @swiftdata-pro, @swift-concurrency-pro, @swift-testing-pro

**Dependencies:** Start only after `docs/superpowers/plans/2026-03-22-portu-data-foundation.md` is complete.

---

## File Map

```
Portu/
├── Packages/PortuUI/
│   ├── Sources/PortuUI/
│   │   ├── Components/
│   │   │   ├── CurrencyText.swift
│   │   │   ├── SectionHeader.swift                  # new
│   │   │   ├── StatCard.swift
│   │   │   ├── SyncStatusBadge.swift                # new
│   │   │   └── TimeRangePicker.swift                # new
│   │   └── Theme/PortuTheme.swift
│   └── Tests/PortuUITests/
│       └── PortuUITests.swift
├── Sources/Portu/
│   ├── App/
│   │   ├── AppState.swift
│   │   ├── ContentView.swift
│   │   └── SidebarSection.swift                     # new
│   ├── Features/
│   │   ├── Overview/
│   │   │   ├── OverviewView.swift                   # new
│   │   │   ├── OverviewViewModel.swift              # new
│   │   │   ├── Models/
│   │   │   │   ├── OverviewInspectorMode.swift      # new
│   │   │   │   └── OverviewTab.swift                # new
│   │   │   └── Sections/
│   │   │       ├── OverviewChartSection.swift       # new
│   │   │       ├── OverviewHeader.swift             # new
│   │   │       ├── OverviewInspector.swift          # new
│   │   │       ├── OverviewSummaryCards.swift       # new
│   │   │       └── OverviewTabbedTokens.swift       # new
│   │   ├── Portfolio/
│   │   │   ├── HoldingRow.swift                     # remove or fold into shared formatting
│   │   │   ├── PortfolioView.swift                  # delete or turn into redirect shell
│   │   │   └── SummaryCards.swift                   # delete or replace
│   │   ├── Settings/SettingsView.swift
│   │   └── Sidebar/SidebarView.swift
│   └── Features/Shared/
│       ├── AssetValueFormatter.swift                # new
│       └── QuerySnapshots.swift                     # new
└── Tests/PortuTests/
    ├── NavigationTests.swift                        # new
    └── OverviewViewModelTests.swift                 # new
```

---

### Task 1: Expand the app shell to the production sidebar and routing model

**Files:**
- Modify: `Sources/Portu/App/AppState.swift`
- Modify: `Sources/Portu/App/ContentView.swift`
- Create: `Sources/Portu/App/SidebarSection.swift`
- Modify: `Sources/Portu/Features/Sidebar/SidebarView.swift`
- Test: `Tests/PortuTests/NavigationTests.swift`

- [ ] **Step 1: Write failing routing tests for the new sidebar sections**

```swift
@Test func sidebarSectionDefaultsToOverview() {
    let state = AppState()
    #expect(state.selectedSection == .overview)
}

@Test func contentViewRoutesKnownSections() {
    #expect(SidebarSection.allCases.contains(.performance))
    #expect(SidebarSection.allCases.contains(.allAssets))
}
```

- [ ] **Step 2: Run the app routing tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/NavigationTests test`

Expected: FAIL because `SidebarSection` still exposes `.portfolio` / `.account` only.

- [ ] **Step 3: Implement the production navigation enum and sidebar layout**

```swift
enum SidebarSection: Hashable, CaseIterable, Sendable {
    case overview
    case exposure
    case performance
    case allAssets
    case allPositions
    case accounts
}
```

- [ ] **Step 4: Re-run the routing tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/NavigationTests test`

Expected: PASS with `NavigationSplitView` routing every main destination.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/App/AppState.swift Sources/Portu/App/ContentView.swift Sources/Portu/App/SidebarSection.swift Sources/Portu/Features/Sidebar/SidebarView.swift Tests/PortuTests/NavigationTests.swift
git commit -m "feat: expand app navigation for production sidebar sections"
```

---

### Task 2: Build the Overview aggregation layer against live positions, prices, and snapshots

**Files:**
- Create: `Sources/Portu/Features/Overview/OverviewViewModel.swift`
- Create: `Sources/Portu/Features/Overview/Models/OverviewTab.swift`
- Create: `Sources/Portu/Features/Shared/AssetValueFormatter.swift`
- Create: `Sources/Portu/Features/Shared/QuerySnapshots.swift`
- Test: `Tests/PortuTests/OverviewViewModelTests.swift`

- [ ] **Step 1: Write failing tests for Overview totals, fallback pricing, and tab contents**

```swift
@Test func overviewViewModelComputesTotalAnd24hChange() throws {
    let viewModel = OverviewViewModel.fixture(
        prices: ["ethereum": 3200],
        changes24h: ["ethereum": 4.5]
    )

    #expect(viewModel.totalValue == 6400)
    #expect(viewModel.absoluteChange24h == 288)
}

@Test func borrowRowsRemainPositiveButAreTaggedBorrow() throws {
    let row = try #require(OverviewViewModel.fixture().borrowingRows.first)
    #expect(row.roleLabel == "Borrow")
    #expect(row.displayValue > 0)
}
```

- [ ] **Step 2: Run the Overview view-model tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/OverviewViewModelTests test`

Expected: FAIL with missing aggregation helpers and missing Overview-specific row models.

- [ ] **Step 3: Implement feature-local aggregation helpers**

```swift
@MainActor
@Observable
final class OverviewViewModel {
    var totalValue: Decimal
    var absoluteChange24h: Decimal
    var percentageChange24h: Decimal
    var topAssets: [TopAssetSlice]
    var borrowingRows: [OverviewTokenRow]
}
```

- [ ] **Step 4: Re-run the Overview view-model tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/OverviewViewModelTests test`

Expected: PASS with coverage for signed aggregations, fallback pricing, and token-row tab selection.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Overview/OverviewViewModel.swift Sources/Portu/Features/Overview/Models/OverviewTab.swift Sources/Portu/Features/Shared/AssetValueFormatter.swift Sources/Portu/Features/Shared/QuerySnapshots.swift Tests/PortuTests/OverviewViewModelTests.swift
git commit -m "feat: add overview aggregation layer for charts and token tabs"
```

---

### Task 3: Implement the Overview main column

**Files:**
- Create: `Sources/Portu/Features/Overview/OverviewView.swift`
- Create: `Sources/Portu/Features/Overview/Sections/OverviewHeader.swift`
- Create: `Sources/Portu/Features/Overview/Sections/OverviewChartSection.swift`
- Create: `Sources/Portu/Features/Overview/Sections/OverviewSummaryCards.swift`
- Create: `Sources/Portu/Features/Overview/Sections/OverviewTabbedTokens.swift`
- Modify: `Packages/PortuUI/Sources/PortuUI/Components/StatCard.swift`
- Create: `Packages/PortuUI/Sources/PortuUI/Components/SectionHeader.swift`
- Create: `Packages/PortuUI/Sources/PortuUI/Components/TimeRangePicker.swift`
- Modify: `Sources/Portu/Features/Portfolio/PortfolioView.swift`

- [ ] **Step 1: Write a failing smoke test for the Overview screen**

```swift
@Test func overviewViewRendersSyncActionAndTimeRanges() {
    let body = OverviewView.previewBody
    #expect(body.contains("Sync"))
    #expect(body.contains("1m"))
}
```

- [ ] **Step 2: Run the Overview smoke test**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/OverviewViewModelTests test`

Expected: FAIL because the new `OverviewView` and reusable controls are missing.

- [ ] **Step 3: Implement the main Overview column**

```swift
struct OverviewView: View {
    var body: some View {
        ScrollView {
            OverviewHeader(...)
            OverviewChartSection(...)
            OverviewSummaryCards(...)
            OverviewTabbedTokens(...)
        }
        .navigationTitle("Overview")
    }
}
```

- [ ] **Step 4: Run the app tests and build the scheme**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with the Overview feature compiling cleanly against the new foundation.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Overview Sources/Portu/Features/Portfolio/PortfolioView.swift Packages/PortuUI/Sources/PortuUI/Components/StatCard.swift Packages/PortuUI/Sources/PortuUI/Components/SectionHeader.swift Packages/PortuUI/Sources/PortuUI/Components/TimeRangePicker.swift
git commit -m "feat: build overview dashboard main column"
```

---

### Task 4: Implement the Overview inspector and sync-status presentation

**Files:**
- Create: `Sources/Portu/Features/Overview/Models/OverviewInspectorMode.swift`
- Create: `Sources/Portu/Features/Overview/Sections/OverviewInspector.swift`
- Create: `Packages/PortuUI/Sources/PortuUI/Components/SyncStatusBadge.swift`
- Modify: `Packages/PortuUI/Sources/PortuUI/Theme/PortuTheme.swift`
- Modify: `Sources/Portu/App/ContentView.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Add a failing test for partial-sync badge rendering**

```swift
@Test func syncStatusBadgeHighlightsCompletedWithErrors() {
    let badge = SyncStatusBadge(status: .completedWithErrors(failedAccounts: ["Kraken"]))
    #expect(badge.tint == PortuTheme.warning)
}
```

- [ ] **Step 2: Run the relevant tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/OverviewViewModelTests test`

Expected: FAIL because the badge and inspector presentation layer do not exist yet.

- [ ] **Step 3: Implement the inspector panel and shared sync-status UI**

```swift
struct OverviewInspector: View {
    let topAssets: [TopAssetSlice]
    let watchlist: [WatchlistRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TopAssetsDonut(...)
            PricesWatchlist(...)
        }
    }
}
```

- [ ] **Step 4: Re-run the full app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with Overview fully wired as the default app destination.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Overview/Models/OverviewInspectorMode.swift Sources/Portu/Features/Overview/Sections/OverviewInspector.swift Packages/PortuUI/Sources/PortuUI/Components/SyncStatusBadge.swift Packages/PortuUI/Sources/PortuUI/Theme/PortuTheme.swift Sources/Portu/App/ContentView.swift Sources/Portu/Features/Settings/SettingsView.swift
git commit -m "feat: add overview inspector and sync status presentation"
```
