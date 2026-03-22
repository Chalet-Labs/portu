# Portu Exposure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Exposure workspace with spot assets, liabilities, and net exposure shown by category and by asset.

**Architecture:** Treat Exposure as a pure computed view over current `PositionToken` rows, with no new persistence. Put the sign-sensitive math in a dedicated view model so the category table, asset table, and summary cards share one canonical implementation of the exposure rules.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, PortuUI, Swift Testing

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
│       └── Exposure/
│           ├── ExposureView.swift                     # new
│           ├── ExposureViewModel.swift                # new
│           ├── Models/
│           │   ├── ExposureDisplayMode.swift          # new
│           │   └── ExposureRow.swift                  # new
│           └── Sections/
│               ├── ExposureSummaryCards.swift         # new
│               └── ExposureTable.swift                # new
└── Tests/PortuTests/
    └── ExposureViewModelTests.swift                   # new
```

---

### Task 1: Build the exposure aggregation engine

**Files:**
- Create: `Sources/Portu/Features/Exposure/ExposureViewModel.swift`
- Create: `Sources/Portu/Features/Exposure/Models/ExposureDisplayMode.swift`
- Create: `Sources/Portu/Features/Exposure/Models/ExposureRow.swift`
- Test: `Tests/PortuTests/ExposureViewModelTests.swift`

- [ ] **Step 1: Write failing tests for spot assets, liabilities, and net exposure**

```swift
@Test func exposureSeparatesAssetsAndLiabilities() throws {
    let row = try #require(ExposureViewModel.fixture().categoryRows.first(where: { $0.name == "Major" }))
    #expect(row.spotAssets == 10000)
    #expect(row.liabilities == 3000)
    #expect(row.spotNet == 7000)
}

@Test func netExposureExcludesStablecoins() {
    #expect(ExposureViewModel.fixture().netExposureExcludingStablecoins == 7000)
}
```

- [ ] **Step 2: Run the exposure tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/ExposureViewModelTests test`

Expected: FAIL because the exposure aggregation layer does not exist.

- [ ] **Step 3: Implement the sign-aware exposure math**

```swift
@MainActor
@Observable
final class ExposureViewModel {
    var displayMode: ExposureDisplayMode = .category
    var categoryRows: [ExposureRow] = []
    var assetRows: [ExposureRow] = []
    var netExposureExcludingStablecoins: Decimal = 0
}
```

- [ ] **Step 4: Re-run the exposure tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/ExposureViewModelTests test`

Expected: PASS with the exposure formulas covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Exposure/ExposureViewModel.swift Sources/Portu/Features/Exposure/Models Tests/PortuTests/ExposureViewModelTests.swift
git commit -m "feat: add exposure aggregation logic"
```

---

### Task 2: Implement the Exposure summary cards and table workspace

**Files:**
- Create: `Sources/Portu/Features/Exposure/ExposureView.swift`
- Create: `Sources/Portu/Features/Exposure/Sections/ExposureSummaryCards.swift`
- Create: `Sources/Portu/Features/Exposure/Sections/ExposureTable.swift`
- Modify: `Sources/Portu/App/ContentView.swift`

- [ ] **Step 1: Add a failing smoke test for the display-mode toggle**

```swift
@Test func exposureDisplayModeDefaultsToCategory() {
    #expect(ExposureViewModel().displayMode == .category)
}
```

- [ ] **Step 2: Run the exposure tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/ExposureViewModelTests test`

Expected: FAIL because the view layer and route are missing.

- [ ] **Step 3: Implement the feature UI**

```swift
struct ExposureView: View {
    var body: some View {
        VStack(spacing: 20) {
            ExposureSummaryCards(...)
            ExposureTable(...)
        }
        .navigationTitle("Exposure")
    }
}
```

- [ ] **Step 4: Re-run the app build**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED with `.exposure` routed to the new feature.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Exposure/ExposureView.swift Sources/Portu/Features/Exposure/Sections/ExposureSummaryCards.swift Sources/Portu/Features/Exposure/Sections/ExposureTable.swift Sources/Portu/App/ContentView.swift
git commit -m "feat: add exposure workspace"
```

---

### Task 3: Finish asset-mode toggling and full-app verification

**Files:**
- Modify: `Sources/Portu/Features/Exposure/ExposureView.swift`
- Modify: `Sources/Portu/Features/Exposure/ExposureViewModel.swift`
- Modify: `Sources/Portu/Features/Exposure/Sections/ExposureTable.swift`

- [ ] **Step 1: Add a failing test for asset display mode**

```swift
@Test func assetModeShowsFlatAssetRows() {
    let viewModel = ExposureViewModel.fixture()
    viewModel.displayMode = .asset
    #expect(viewModel.visibleRows.allSatisfy { $0.assetSymbol != nil })
}
```

- [ ] **Step 2: Run the exposure tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/ExposureViewModelTests test`

Expected: FAIL because the toggle and visible-row projection are incomplete.

- [ ] **Step 3: Implement the display-mode switch and empty states**

```swift
Picker("Display", selection: $viewModel.displayMode) {
    Text("By Category").tag(ExposureDisplayMode.category)
    Text("By Asset").tag(ExposureDisplayMode.asset)
}
```

- [ ] **Step 4: Re-run the full app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with both exposure modes working off the same aggregation engine.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Exposure/ExposureView.swift Sources/Portu/Features/Exposure/ExposureViewModel.swift Sources/Portu/Features/Exposure/Sections/ExposureTable.swift
git commit -m "feat: finish exposure display modes"
```

