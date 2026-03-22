# Portu All Positions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the All Positions workspace with grouped protocol sections, filter sidebar, and manual-position entry for manual accounts.

**Architecture:** Query active accounts and positions directly with SwiftData, centralize grouping and filter math in a feature-local view model, and keep manual-entry mutations isolated behind one editor surface so sign conventions and asset upsert rules stay consistent. Read-only grouping can proceed independently, but the final plan output should include the manual-entry flow rather than deferring it.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, PortuUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Skills to use:** @swift-architecture-skill, @swiftui-pro, @swiftdata-pro, @swift-testing-pro

**Dependencies:** Start after `docs/superpowers/plans/2026-03-22-portu-data-foundation.md` and `docs/superpowers/plans/2026-03-22-portu-overview-navigation.md`. Execute after `docs/superpowers/plans/2026-03-22-portu-accounts.md` if you want manual-account creation available before manual-position entry.

---

## File Map

```
Portu/
├── Sources/Portu/
│   ├── App/ContentView.swift
│   └── Features/
│       └── AllPositions/
│           ├── AllPositionsView.swift                 # new
│           ├── AllPositionsViewModel.swift            # new
│           ├── ManualPositionEditor.swift             # new
│           ├── Models/
│           │   ├── PositionFilter.swift               # new
│           │   ├── PositionSectionModel.swift         # new
│           │   └── PositionTokenRowModel.swift        # new
│           └── Sections/
│               ├── ManualPositionButton.swift         # new
│               ├── PositionFilterSidebar.swift        # new
│               └── PositionSectionView.swift          # new
└── Tests/PortuTests/
    ├── AllPositionsViewModelTests.swift               # new
    └── ManualPositionEditorTests.swift                # new
```

---

### Task 1: Build grouping and filtering for position data

**Files:**
- Create: `Sources/Portu/Features/AllPositions/AllPositionsViewModel.swift`
- Create: `Sources/Portu/Features/AllPositions/Models/PositionFilter.swift`
- Create: `Sources/Portu/Features/AllPositions/Models/PositionSectionModel.swift`
- Create: `Sources/Portu/Features/AllPositions/Models/PositionTokenRowModel.swift`
- Test: `Tests/PortuTests/AllPositionsViewModelTests.swift`

- [ ] **Step 1: Write failing tests for grouped sections and token-row display contracts**

```swift
@Test func positionsGroupByTypeThenProtocol() throws {
    let sections = AllPositionsViewModel.fixture().sections
    #expect(sections.first?.title == "Idle Onchain")
    #expect(sections.first?.children.first?.protocolName == "Aave V3")
}

@Test func borrowRowsStayPositiveAndExposeRoleLabel() throws {
    let row = try #require(AllPositionsViewModel.fixture().sections[1].children[0].rows.first)
    #expect(row.roleLabel == "Borrow")
    #expect(row.displayAmount > 0)
}
```

- [ ] **Step 2: Run the grouped-position tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllPositionsViewModelTests test`

Expected: FAIL because the grouping layer and row models do not exist.

- [ ] **Step 3: Implement the grouped section projection**

```swift
@MainActor
@Observable
final class AllPositionsViewModel {
    var selectedFilter = PositionFilter.all
    var sections: [PositionSectionModel] = []
    var protocolOptions: [String] = []
}
```

- [ ] **Step 4: Re-run the grouped-position tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllPositionsViewModelTests test`

Expected: PASS with grouping, totals, and token row contracts covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllPositions/AllPositionsViewModel.swift Sources/Portu/Features/AllPositions/Models Tests/PortuTests/AllPositionsViewModelTests.swift
git commit -m "feat: add all positions grouping and filter models"
```

---

### Task 2: Implement the grouped positions workspace and filter sidebar

**Files:**
- Create: `Sources/Portu/Features/AllPositions/AllPositionsView.swift`
- Create: `Sources/Portu/Features/AllPositions/Sections/PositionSectionView.swift`
- Create: `Sources/Portu/Features/AllPositions/Sections/PositionFilterSidebar.swift`
- Modify: `Sources/Portu/App/ContentView.swift`

- [ ] **Step 1: Add a failing smoke test for the filter sidebar**

```swift
@Test func positionsViewExposesTypeAndProtocolFilters() {
    #expect(PositionFilter.allCases.contains(.lending))
    #expect(PositionFilter.allCases.contains(.liquidityPool))
}
```

- [ ] **Step 2: Run the feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllPositionsViewModelTests test`

Expected: FAIL because the sidebar views and route are missing.

- [ ] **Step 3: Implement the main split layout**

```swift
struct AllPositionsView: View {
    var body: some View {
        HSplitView {
            ScrollView { PositionSectionView(...) }
            PositionFilterSidebar(...)
        }
        .navigationTitle("All Positions")
    }
}
```

- [ ] **Step 4: Re-run the feature tests and app build**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED with `.allPositions` routed to the new feature.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllPositions/AllPositionsView.swift Sources/Portu/Features/AllPositions/Sections/PositionSectionView.swift Sources/Portu/Features/AllPositions/Sections/PositionFilterSidebar.swift Sources/Portu/App/ContentView.swift
git commit -m "feat: add all positions workspace and filters"
```

---

### Task 3: Add manual position creation for manual accounts

**Files:**
- Create: `Sources/Portu/Features/AllPositions/ManualPositionEditor.swift`
- Create: `Sources/Portu/Features/AllPositions/Sections/ManualPositionButton.swift`
- Test: `Tests/PortuTests/ManualPositionEditorTests.swift`

- [ ] **Step 1: Write failing tests for manual position validation and asset creation**

```swift
@Test func manualEditorCreatesIdlePositionForManualAccount() throws {
    let harness = try ManualPositionEditorHarness.make()
    try harness.submit(amount: 2, symbol: "SOL", accountName: "Ledger Notes")

    #expect(harness.savedPositions.count == 1)
    #expect(harness.savedPositions[0].positionType == .idle)
}
```

- [ ] **Step 2: Run the manual-editor tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/ManualPositionEditorTests test`

Expected: FAIL because the editor surface and save path are missing.

- [ ] **Step 3: Implement the editor sheet and save flow**

```swift
struct ManualPositionEditor: View {
    @State private var amount = Decimal.zero
    @State private var selectedAsset: Asset?
    @State private var positionType: PositionType = .idle
}
```

- [ ] **Step 4: Re-run the manual-editor tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/ManualPositionEditorTests test`

Expected: PASS with validation and save behavior covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllPositions/ManualPositionEditor.swift Sources/Portu/Features/AllPositions/Sections/ManualPositionButton.swift Tests/PortuTests/ManualPositionEditorTests.swift
git commit -m "feat: add manual position entry flow"
```

---

### Task 4: Finish the filter polish and end-to-end app verification

**Files:**
- Modify: `Sources/Portu/Features/AllPositions/AllPositionsView.swift`
- Modify: `Sources/Portu/Features/AllPositions/AllPositionsViewModel.swift`
- Modify: `Sources/Portu/Features/AllPositions/Sections/PositionFilterSidebar.swift`

- [ ] **Step 1: Add a failing test for protocol-filter totals**

```swift
@Test func selectedProtocolFilterUpdatesTotals() throws {
    let viewModel = AllPositionsViewModel.fixture()
    viewModel.selectedProtocol = "Aave V3"
    #expect(viewModel.visibleUSDTotal == 1234)
}
```

- [ ] **Step 2: Run the position feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllPositionsViewModelTests test`

Expected: FAIL because the final filter-total coupling is incomplete.

- [ ] **Step 3: Implement the final filter-state coupling and empty states**

```swift
if viewModel.sections.isEmpty {
    ContentUnavailableView("No Matching Positions", systemImage: "line.3.horizontal.decrease.circle")
}
```

- [ ] **Step 4: Re-run the full app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with grouped list, filters, and manual entry working together.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllPositions/AllPositionsView.swift Sources/Portu/Features/AllPositions/AllPositionsViewModel.swift Sources/Portu/Features/AllPositions/Sections/PositionFilterSidebar.swift
git commit -m "feat: finish all positions filtering polish"
```

