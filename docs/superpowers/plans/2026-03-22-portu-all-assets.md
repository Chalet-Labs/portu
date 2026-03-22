# Portu All Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the All Assets workspace with sortable tables, grouping controls, CSV export, and drill-in navigation to asset detail.

**Architecture:** Keep persisted reads in SwiftUI via `@Query`, push search, sorting, grouping, and export shaping into a feature-local view model, and treat the tabbed feature as one routing surface with three production tabs plus one placeholder tab. Reuse the sign conventions and price fallback rules defined in the data-foundation plan rather than recomputing view-specific rules ad hoc.

**Tech Stack:** Swift 6.2, SwiftUI `Table`, SwiftData, UniformTypeIdentifiers, PortuUI, Swift Testing

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
│       ├── AllAssets/
│       │   ├── AllAssetsView.swift                    # new
│       │   ├── AllAssetsViewModel.swift               # new
│       │   ├── CSV/AssetsCSVExporter.swift            # new
│       │   ├── Models/
│       │   │   ├── AllAssetsGrouping.swift            # new
│       │   │   ├── AllAssetsTab.swift                 # new
│       │   │   ├── AssetTableRow.swift                # new
│       │   │   ├── NetworkTableRow.swift              # new
│       │   │   └── PlatformTableRow.swift             # new
│       │   └── Tabs/
│       │       ├── AssetsTabView.swift                # new
│       │       ├── NetworksTabView.swift              # new
│       │       ├── NFTPlaceholderTabView.swift        # new
│       │       └── PlatformsTabView.swift             # new
│       └── Shared/CSVDocument.swift                   # new
└── Tests/PortuTests/
    ├── AllAssetsExportTests.swift                     # new
    └── AllAssetsViewModelTests.swift                  # new
```

---

### Task 1: Build the All Assets query and tab state layer

**Files:**
- Create: `Sources/Portu/Features/AllAssets/AllAssetsViewModel.swift`
- Create: `Sources/Portu/Features/AllAssets/Models/AllAssetsTab.swift`
- Create: `Sources/Portu/Features/AllAssets/Models/AllAssetsGrouping.swift`
- Create: `Sources/Portu/Features/AllAssets/Models/AssetTableRow.swift`
- Create: `Sources/Portu/Features/AllAssets/Models/PlatformTableRow.swift`
- Create: `Sources/Portu/Features/AllAssets/Models/NetworkTableRow.swift`
- Test: `Tests/PortuTests/AllAssetsViewModelTests.swift`

- [ ] **Step 1: Write failing tests for asset aggregation, grouping, and search**

```swift
@Test func assetRowsNetBorrowAgainstSupply() throws {
    let viewModel = AllAssetsViewModel.fixture()
    let eth = try #require(viewModel.assetRows.first(where: { $0.symbol == "ETH" }))

    #expect(eth.netAmount == 1.25)
    #expect(eth.value < eth.grossValue)
}

@Test func networksTabBucketsNilChainsAsOffChainCustodial() throws {
    let viewModel = AllAssetsViewModel.fixture()
    let row = try #require(viewModel.networkRows.first(where: { $0.title == "Off-chain / Custodial" }))
    #expect(row.positionCount == 1)
}
```

- [ ] **Step 2: Run the feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllAssetsViewModelTests test`

Expected: FAIL because the feature-local row models and aggregation code do not exist.

- [ ] **Step 3: Implement the feature state and row projection layer**

```swift
@MainActor
@Observable
final class AllAssetsViewModel {
    var selectedTab: AllAssetsTab = .assets
    var searchText = ""
    var grouping: AllAssetsGrouping = .category
    var assetRows: [AssetTableRow] = []
    var platformRows: [PlatformTableRow] = []
    var networkRows: [NetworkTableRow] = []
}
```

- [ ] **Step 4: Re-run the feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllAssetsViewModelTests test`

Expected: PASS with row shaping for assets, platforms, and networks covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllAssets/AllAssetsViewModel.swift Sources/Portu/Features/AllAssets/Models Tests/PortuTests/AllAssetsViewModelTests.swift
git commit -m "feat: add all assets aggregation models"
```

---

### Task 2: Implement the Assets tab with sorting, search, and CSV export

**Files:**
- Create: `Sources/Portu/Features/AllAssets/AllAssetsView.swift`
- Create: `Sources/Portu/Features/AllAssets/Tabs/AssetsTabView.swift`
- Create: `Sources/Portu/Features/AllAssets/CSV/AssetsCSVExporter.swift`
- Create: `Sources/Portu/Features/Shared/CSVDocument.swift`
- Modify: `Sources/Portu/App/ContentView.swift`
- Test: `Tests/PortuTests/AllAssetsExportTests.swift`

- [ ] **Step 1: Write failing tests for CSV export and default route wiring**

```swift
@Test func csvExporterWritesHeaderAndRows() throws {
    let csv = AssetsCSVExporter().makeCSV(rows: [.fixture(symbol: "ETH")])
    #expect(csv.contains("Symbol,Name,Category,Net Amount,Price,Value"))
    #expect(csv.contains("ETH"))
}
```

- [ ] **Step 2: Run the asset export tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllAssetsExportTests test`

Expected: FAIL because the exporter and `AllAssetsView` route are missing.

- [ ] **Step 3: Build the main All Assets tabbed surface**

```swift
struct AllAssetsView: View {
    var body: some View {
        TabView {
            AssetsTabView(...)
                .tabItem { Label("Assets", systemImage: "bitcoinsign.square") }
            NFTPlaceholderTabView()
                .tabItem { Label("NFTs", systemImage: "photo.stack") }
            PlatformsTabView(...)
                .tabItem { Label("Platforms", systemImage: "building.columns") }
            NetworksTabView(...)
                .tabItem { Label("Networks", systemImage: "globe") }
        }
    }
}
```

- [ ] **Step 4: Re-run the export tests and build the app scheme**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllAssetsExportTests test`

Expected: PASS with export and route coverage.

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED with `.allAssets` routed to the new feature.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllAssets/AllAssetsView.swift Sources/Portu/Features/AllAssets/Tabs/AssetsTabView.swift Sources/Portu/Features/AllAssets/CSV/AssetsCSVExporter.swift Sources/Portu/Features/Shared/CSVDocument.swift Sources/Portu/App/ContentView.swift Tests/PortuTests/AllAssetsExportTests.swift
git commit -m "feat: add all assets table and csv export"
```

---

### Task 3: Implement the Platforms and Networks tabs

**Files:**
- Create: `Sources/Portu/Features/AllAssets/Tabs/PlatformsTabView.swift`
- Create: `Sources/Portu/Features/AllAssets/Tabs/NetworksTabView.swift`
- Modify: `Sources/Portu/Features/AllAssets/AllAssetsViewModel.swift`
- Test: `Tests/PortuTests/AllAssetsViewModelTests.swift`

- [ ] **Step 1: Add failing tests for platform and network row ordering**

```swift
@Test func platformRowsSortByUsdBalanceDescending() throws {
    let rows = AllAssetsViewModel.fixture().platformRows
    #expect(rows.map(\.name) == ["Aave V3", "Lido"])
}
```

- [ ] **Step 2: Run the feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllAssetsViewModelTests test`

Expected: FAIL because the secondary tab views and row ordering rules are incomplete.

- [ ] **Step 3: Implement the derived tabs**

```swift
struct PlatformsTabView: View {
    let rows: [PlatformTableRow]
    var body: some View { Table(rows) { ... } }
}

struct NetworksTabView: View {
    let rows: [NetworkTableRow]
    var body: some View { Table(rows) { ... } }
}
```

- [ ] **Step 4: Re-run the feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AllAssetsViewModelTests test`

Expected: PASS with grouped platform and chain summaries covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllAssets/Tabs/PlatformsTabView.swift Sources/Portu/Features/AllAssets/Tabs/NetworksTabView.swift Sources/Portu/Features/AllAssets/AllAssetsViewModel.swift Tests/PortuTests/AllAssetsViewModelTests.swift
git commit -m "feat: add all assets platform and network tabs"
```

---

### Task 4: Add the NFT placeholder and asset-detail drill-in affordances

**Files:**
- Create: `Sources/Portu/Features/AllAssets/Tabs/NFTPlaceholderTabView.swift`
- Modify: `Sources/Portu/Features/AllAssets/Tabs/AssetsTabView.swift`
- Modify: `Sources/Portu/Features/AllAssets/AllAssetsView.swift`

- [ ] **Step 1: Write a failing smoke test for the placeholder contract**

```swift
@Test func nftTabShowsComingSoonPlaceholder() {
    #expect(NFTPlaceholderTabView.placeholderText == "NFT tracking coming soon")
}
```

- [ ] **Step 2: Run the app tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: FAIL because the NFT placeholder view and row navigation contract are missing.

- [ ] **Step 3: Implement the placeholder and `NavigationLink(value:)` rows**

```swift
struct NFTPlaceholderTabView: View {
    static let placeholderText = "NFT tracking coming soon"
    var body: some View { ContentUnavailableView(placeholderText, systemImage: "photo.stack") }
}
```

- [ ] **Step 4: Re-run the app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with the All Assets workspace complete and ready to hand off to the asset-detail plan.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/AllAssets/Tabs/NFTPlaceholderTabView.swift Sources/Portu/Features/AllAssets/Tabs/AssetsTabView.swift Sources/Portu/Features/AllAssets/AllAssetsView.swift
git commit -m "feat: finish all assets placeholder and drill-in navigation"
```

