# Phase 3: All Assets View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the All Assets view with 4 sub-tabs: Assets (sortable table), NFTs (placeholder), Platforms, Networks.

**Architecture:** Tabbed view. Assets tab uses SwiftUI `Table` with sortable columns. Data from `@Query` on PositionToken grouped by Asset. Net Amount per asset computed using sign convention (borrow subtracts, reward excluded).

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Views §2)

**Depends on:** Plans 01-03 must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/AllAssets/AllAssetsView.swift`
- `Sources/Portu/Features/AllAssets/AssetsTab.swift`
- `Sources/Portu/Features/AllAssets/PlatformsTab.swift`
- `Sources/Portu/Features/AllAssets/NetworksTab.swift`

---

### Task 1: AllAssetsView shell with tab switching

**Files:**
- Create: `Sources/Portu/Features/AllAssets/AllAssetsView.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/Portu/Features/AllAssets
```

- [ ] **Step 2: Write AllAssetsView**

```swift
// Sources/Portu/Features/AllAssets/AllAssetsView.swift
import SwiftUI

struct AllAssetsView: View {
    @State private var selectedTab: AssetTab = .assets

    enum AssetTab: String, CaseIterable {
        case assets = "Assets"
        case nfts = "NFTs"
        case platforms = "Platforms"
        case networks = "Networks"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(AssetTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .assets: AssetsTab()
            case .nfts: nftPlaceholder
            case .platforms: PlatformsTab()
            case .networks: NetworksTab()
            }
        }
        .navigationTitle("All Assets")
    }

    private var nftPlaceholder: some View {
        ContentUnavailableView(
            "NFT Tracking",
            systemImage: "photo.artframe",
            description: Text("NFT tracking coming soon")
        )
    }
}
```

- [ ] **Step 3: Wire into ContentView**

Update `ContentView.swift` to replace the placeholder:
```swift
case .allAssets:
    AllAssetsView()
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/AllAssets/AllAssetsView.swift Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add AllAssetsView shell with 4 sub-tabs
EOF
)"
```

---

### Task 2: Assets tab — sortable table with aggregated net amounts

**Files:**
- Create: `Sources/Portu/Features/AllAssets/AssetsTab.swift`

The Assets tab shows one row per Asset, with **aggregated** Net Amount across all accounts. This uses the "Aggregated asset row" display rules from the spec:
- Net Amount = sum(positive role amounts) − sum(borrow amounts) for same Asset
- Value = netAmount × livePrice (can be negative if borrow > supply)
- Price fallback: weighted average from sync-time values when no coinGeckoId

- [ ] **Step 1: Write AssetsTab**

```swift
// Sources/Portu/Features/AllAssets/AssetsTab.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct AssetsTab: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AssetRowData.value, order: .reverse)]

    private struct AssetRowData: Identifiable {
        let id: UUID        // Asset.id
        let symbol: String
        let name: String
        let category: AssetCategory
        let netAmount: Decimal
        let price: Decimal
        let value: Decimal
        let hasLivePrice: Bool
    }

    /// Aggregate tokens by Asset.id, compute net amount
    private var rows: [AssetRowData] {
        // Group tokens by Asset.id
        var assetTokens: [UUID: (asset: Asset, positive: Decimal, borrow: Decimal,
                                  positiveUSD: Decimal, borrowUSD: Decimal)] = [:]

        for token in allTokens {
            guard let asset = token.asset else { continue }
            if token.role.isReward { continue }

            var entry = assetTokens[asset.id] ?? (asset, 0, 0, 0, 0)
            if token.role.isBorrow {
                entry.borrow += token.amount
                entry.borrowUSD += token.usdValue
            } else if token.role.isPositive {
                entry.positive += token.amount
                entry.positiveUSD += token.usdValue
            }
            assetTokens[asset.id] = entry
        }

        return assetTokens.values.compactMap { entry in
            let netAmount = entry.positive - entry.borrow
            let hasLive = entry.asset.coinGeckoId.flatMap { appState.prices[$0] } != nil

            let price: Decimal
            let value: Decimal

            if let cgId = entry.asset.coinGeckoId, let livePrice = appState.prices[cgId] {
                price = livePrice
                value = netAmount * livePrice
            } else {
                // Sync-time fallback: weighted average price
                if entry.positive > 0 {
                    price = entry.positiveUSD / entry.positive
                } else if entry.borrow > 0 {
                    price = entry.borrowUSD / entry.borrow
                } else {
                    price = 0
                }
                value = entry.positiveUSD - entry.borrowUSD
            }

            return AssetRowData(
                id: entry.asset.id,
                symbol: entry.asset.symbol,
                name: entry.asset.name,
                category: entry.asset.category,
                netAmount: netAmount,
                price: price,
                value: value,
                hasLivePrice: hasLive
            )
        }
        .filter { searchText.isEmpty || $0.symbol.localizedCaseInsensitiveContains(searchText)
                   || $0.name.localizedCaseInsensitiveContains(searchText) }
        .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search assets...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal)
            .padding(.bottom, 8)

            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Symbol", value: \.symbol) { row in
                    NavigationLink(value: row.id) {
                        Text(row.symbol).fontWeight(.medium)
                    }
                }
                .width(min: 60, ideal: 80)

                TableColumn("Name", value: \.name) { row in
                    Text(row.name)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Category") { row in
                    Text(row.category.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                .width(min: 80, ideal: 100)

                TableColumn("Net Amount", value: \.netAmount) { row in
                    Text(row.netAmount, format: .number.precision(.fractionLength(2...8)))
                        .foregroundStyle(row.netAmount < 0 ? .red : .primary)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Price", value: \.price) { row in
                    HStack(spacing: 4) {
                        Text(row.price, format: .currency(code: "USD"))
                        if !row.hasLivePrice {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Sync-time price — no live data")
                        }
                    }
                }
                .width(min: 80, ideal: 100)

                TableColumn("Value", value: \.value) { row in
                    Text(row.value, format: .currency(code: "USD"))
                        .foregroundStyle(row.value < 0 ? .red : .primary)
                }
                .width(min: 80, ideal: 120)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/AllAssets/AssetsTab.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Assets tab with sortable table and aggregated net amounts

One row per Asset with net amount (borrow subtracted, reward excluded).
Live price from PriceService with sync-time fallback indicator.
Navigates to Asset Detail on row click.
EOF
)"
```

---

### Task 3: Platforms tab

**Files:**
- Create: `Sources/Portu/Features/AllAssets/PlatformsTab.swift`

Table grouped by protocol (Position.protocolId).

- [ ] **Step 1: Write PlatformsTab**

```swift
// Sources/Portu/Features/AllAssets/PlatformsTab.swift
import SwiftUI
import SwiftData
import PortuCore

struct PlatformsTab: View {
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    private struct PlatformRow: Identifiable {
        let id: String // protocolId or "idle"
        let name: String
        let sharePercent: Decimal
        let networkCount: Int
        let positionCount: Int
        let usdBalance: Decimal
    }

    private var rows: [PlatformRow] {
        let totalValue = positions.reduce(Decimal.zero) { $0 + max($1.netUSDValue, 0) }

        var byProtocol: [String: (name: String, chains: Set<String>, count: Int, value: Decimal)] = [:]

        for pos in positions {
            let key = pos.protocolId ?? (pos.positionType == .idle ? "__idle__" : "__unknown__")
            let name = pos.protocolName ?? (pos.positionType == .idle ? "Idle / Wallet" : "Unknown")
            var entry = byProtocol[key] ?? (name, [], 0, 0)
            entry.count += 1
            entry.value += pos.netUSDValue
            if let chain = pos.chain { entry.chains.insert(chain.rawValue) }
            else { entry.chains.insert("off-chain") }
            byProtocol[key] = entry
        }

        return byProtocol.map { (key, entry) in
            PlatformRow(
                id: key,
                name: entry.name,
                sharePercent: totalValue > 0 ? entry.value / totalValue : 0,
                networkCount: entry.chains.count,
                positionCount: entry.count,
                usdBalance: entry.value
            )
        }
        .sorted { $0.usdBalance > $1.usdBalance }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Platform") { row in Text(row.name).fontWeight(.medium) }
            TableColumn("Share %") { row in
                Text(row.sharePercent, format: .percent.precision(.fractionLength(1)))
            }
            TableColumn("# Networks") { row in Text("\(row.networkCount)") }
            TableColumn("# Positions") { row in Text("\(row.positionCount)") }
            TableColumn("USD Balance") { row in
                Text(row.usdBalance, format: .currency(code: "USD"))
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/AllAssets/PlatformsTab.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Platforms tab grouped by protocol
EOF
)"
```

---

### Task 4: Networks tab

**Files:**
- Create: `Sources/Portu/Features/AllAssets/NetworksTab.swift`

Table grouped by chain. `chain == nil` grouped as "Off-chain / Custodial".

- [ ] **Step 1: Write NetworksTab**

```swift
// Sources/Portu/Features/AllAssets/NetworksTab.swift
import SwiftUI
import SwiftData
import PortuCore

struct NetworksTab: View {
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    private struct NetworkRow: Identifiable {
        let id: String
        let name: String
        let sharePercent: Decimal
        let positionCount: Int
        let usdBalance: Decimal
    }

    private var rows: [NetworkRow] {
        let totalValue = positions.reduce(Decimal.zero) { $0 + max($1.netUSDValue, 0) }

        var byChain: [String: (count: Int, value: Decimal)] = [:]
        for pos in positions {
            let key = pos.chain?.rawValue ?? "__offchain__"
            var entry = byChain[key] ?? (0, 0)
            entry.count += 1
            entry.value += pos.netUSDValue
            byChain[key] = entry
        }

        return byChain.map { (key, entry) in
            NetworkRow(
                id: key,
                name: key == "__offchain__" ? "Off-chain / Custodial" : key.capitalized,
                sharePercent: totalValue > 0 ? entry.value / totalValue : 0,
                positionCount: entry.count,
                usdBalance: entry.value
            )
        }
        .sorted { $0.usdBalance > $1.usdBalance }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Network") { row in Text(row.name).fontWeight(.medium) }
            TableColumn("Share %") { row in
                Text(row.sharePercent, format: .percent.precision(.fractionLength(1)))
            }
            TableColumn("# Positions") { row in Text("\(row.positionCount)") }
            TableColumn("USD Balance") { row in
                Text(row.usdBalance, format: .currency(code: "USD"))
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/AllAssets/NetworksTab.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Networks tab grouped by chain
EOF
)"
```

---

### Task 5: Add grouping options and CSV export to Assets tab

**Files:**
- Modify: `Sources/Portu/Features/AllAssets/AssetsTab.swift`

Per spec: "Grouping options (Category, Price Source, Account Group). CSV export."

- [ ] **Step 1: Add grouping picker**

Add a `@State` for grouping mode (None, Category, Price Source, Account Group). When grouping is active, wrap `Table` rows in `Section` headers grouped by the selected field.

- [ ] **Step 2: Add CSV export button**

Add a toolbar button that exports the current table data to CSV using `NSSavePanel`. Format: Symbol, Name, Category, Net Amount, Price, Value.

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/Features/AllAssets/AssetsTab.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add grouping options and CSV export to Assets tab
EOF
)"
```

---

### Task 6: Build and verify

- [ ] **Step 1: Build**

Run: `just build 2>&1 | tail -10`
Expected: SUCCESS

- [ ] **Step 2: Commit any fixes**
