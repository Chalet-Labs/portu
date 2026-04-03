# Phase 3: Asset Detail View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Asset Detail drill-down view — price chart with 3 modes, holdings summary, positions table, and metadata sidebar.

**Architecture:** Pushed via `navigationDestination(for: UUID.self)` from any asset link. Two-column layout: main content (chart + positions table) + right sidebar (metadata). Chart data from AssetSnapshot ($ Value, Amount modes) and CoinGecko historical API (Price mode).

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Swift Charts

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Views §7)

**Depends on:** Plans 01-03 must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/AssetDetail/AssetDetailView.swift`
- `Sources/Portu/Features/AssetDetail/AssetPriceChart.swift`
- `Sources/Portu/Features/AssetDetail/AssetHoldingsSummary.swift`
- `Sources/Portu/Features/AssetDetail/AssetPositionsTable.swift`
- `Sources/Portu/Features/AssetDetail/AssetMetadataSidebar.swift`

---

### Task 1: AssetDetailView shell

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/AssetDetailView.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/Portu/Features/AssetDetail
```

- [ ] **Step 2: Write AssetDetailView**

```swift
// Sources/Portu/Features/AssetDetail/AssetDetailView.swift
import SwiftUI
import SwiftData
import PortuCore

struct AssetDetailView: View {
    let assetId: UUID

    @Query private var assets: [Asset]
    @Environment(AppState.self) private var appState

    private var asset: Asset? {
        assets.first { $0.id == assetId }
    }

    var body: some View {
        if let asset {
            HSplitView {
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Breadcrumb
                        HStack {
                            Button("← Assets") {
                                appState.selectedSection = .allAssets
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            Text(">")
                                .foregroundStyle(.tertiary)
                            Text(asset.symbol)
                                .fontWeight(.medium)
                        }
                        .font(.caption)

                        // Header
                        HStack(alignment: .firstTextBaseline) {
                            Text(asset.name)
                                .font(.title.weight(.semibold))
                            Text(asset.symbol)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let cgId = asset.coinGeckoId, let price = appState.prices[cgId] {
                                VStack(alignment: .trailing) {
                                    Text(price, format: .currency(code: "USD"))
                                        .font(.title2.weight(.semibold))
                                    if let change = appState.priceChanges24h[cgId] {
                                        HStack(spacing: 4) {
                                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            Text(change, format: .percent.precision(.fractionLength(2)))
                                        }
                                        .foregroundStyle(change >= 0 ? .green : .red)
                                    }
                                }
                            }
                        }

                        AssetPriceChart(assetId: assetId, coinGeckoId: asset.coinGeckoId)
                        AssetHoldingsSummary(assetId: assetId)
                        AssetPositionsTable(assetId: assetId)
                    }
                    .padding()
                }
                .frame(minWidth: 500)
                .layoutPriority(3)

                // Right sidebar
                AssetMetadataSidebar(asset: asset)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                    .layoutPriority(1)
            }
        } else {
            ContentUnavailableView("Asset Not Found", systemImage: "questionmark.circle")
        }
    }
}
```

- [ ] **Step 3: Update ContentView navigation destination**

In `ContentView.swift`, update the `navigationDestination` to use `AssetDetailView`:

```swift
.navigationDestination(for: UUID.self) { assetId in
    AssetDetailView(assetId: assetId)
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/ Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add AssetDetailView shell with breadcrumb and header
EOF
)"
```

---

### Task 2: Asset price chart (3 modes)

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/AssetPriceChart.swift`

Three modes: Price (CoinGecko historical), $ Value (AssetSnapshot net), Amount (AssetSnapshot net amount).

- [ ] **Step 1: Write AssetPriceChart**

```swift
// Sources/Portu/Features/AssetDetail/AssetPriceChart.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

struct AssetPriceChart: View {
    let assetId: UUID
    let coinGeckoId: String?

    @Query(sort: \AssetSnapshot.timestamp)
    private var snapshots: [AssetSnapshot]

    @State private var chartMode: ChartMode = .price
    @State private var selectedRange: TimeRange = .oneMonth

    enum ChartMode: String, CaseIterable {
        case price = "Price"
        case dollarValue = "$ Value"
        case amount = "Amount"
    }

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W", oneMonth = "1M", threeMonths = "3M", oneYear = "1Y"

        var startDate: Date {
            let cal = Calendar.current
            let now = Date.now
            return switch self {
            case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
            case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
            case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
            }
        }
    }

    private var assetSnapshots: [AssetSnapshot] {
        snapshots.filter { $0.assetId == assetId && $0.timestamp >= selectedRange.startDate }
    }

    /// Aggregate by timestamp (sum across accounts)
    private var aggregated: [(Date, Decimal, Decimal, Decimal, Decimal)] {
        // (date, grossUSD, borrowUSD, grossAmount, borrowAmount)
        var byDate: [Date: (Decimal, Decimal, Decimal, Decimal)] = [:]
        for s in assetSnapshots {
            let day = Calendar.current.startOfDay(for: s.timestamp)
            var entry = byDate[day] ?? (0, 0, 0, 0)
            entry.0 += s.usdValue
            entry.1 += s.borrowUsdValue
            entry.2 += s.amount
            entry.3 += s.borrowAmount
            byDate[day] = entry
        }
        return byDate.sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.0, $0.value.1, $0.value.2, $0.value.3) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Mode", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            switch chartMode {
            case .price:
                priceChart
            case .dollarValue:
                valueChart
            case .amount:
                amountChart
            }
        }
    }

    // MARK: - Price chart (from CoinGecko historical API)

    private var priceChart: some View {
        Group {
            if coinGeckoId != nil {
                // TODO: Fetch historical prices from CoinGecko /coins/{id}/market_chart
                // For now, show placeholder
                ContentUnavailableView("Price History", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Historical price chart — requires CoinGecko market_chart API integration"))
                    .frame(height: 250)
            } else {
                ContentUnavailableView("No Price Data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Asset has no CoinGecko ID for price history"))
                    .frame(height: 250)
            }
        }
    }

    // MARK: - $ Value chart (net from AssetSnapshot)

    private var valueChart: some View {
        Group {
            if aggregated.isEmpty {
                ContentUnavailableView("No Value Data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Sync your accounts to see value history"))
                    .frame(height: 250)
            } else {
                let isBorrowOnly = aggregated.allSatisfy { $0.1 == 0 && $0.2 > 0 }

                Chart {
                    ForEach(aggregated, id: \.0) { (date, gross, borrow, _, _) in
                        let net = gross - borrow
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Value", net)
                        )
                        .foregroundStyle(net < 0 ? .red : Color.accentColor)

                        AreaMark(
                            x: .value("Date", date),
                            y: .value("Value", net)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [
                                    (net < 0 ? Color.red : Color.accentColor).opacity(0.2),
                                    .clear
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 250)

                if isBorrowOnly {
                    Text("Debt history — this asset is only borrowed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Amount chart (net from AssetSnapshot)

    private var amountChart: some View {
        Group {
            if aggregated.isEmpty {
                ContentUnavailableView("No Amount Data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Sync your accounts to see amount history"))
                    .frame(height: 250)
            } else {
                Chart {
                    ForEach(aggregated, id: \.0) { (date, _, _, grossAmt, borrowAmt) in
                        let net = grossAmt - borrowAmt
                        LineMark(x: .value("Date", date), y: .value("Amount", net))
                            .foregroundStyle(net < 0 ? .red : Color.accentColor)
                    }
                }
                .frame(height: 250)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/AssetPriceChart.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add AssetPriceChart with Price, $ Value, Amount modes

$ Value and Amount modes from AssetSnapshot net values.
Price mode placeholder for CoinGecko historical API integration.
Borrow-only assets show debt history indicator.
EOF
)"
```

---

### Task 3: Holdings summary and positions table

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/AssetHoldingsSummary.swift`
- Create: `Sources/Portu/Features/AssetDetail/AssetPositionsTable.swift`

- [ ] **Step 1: Write AssetHoldingsSummary**

```swift
// Sources/Portu/Features/AssetDetail/AssetHoldingsSummary.swift
import SwiftUI
import SwiftData
import PortuCore

struct AssetHoldingsSummary: View {
    let assetId: UUID

    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    private var assetTokens: [PositionToken] {
        allTokens.filter { $0.asset?.id == assetId }
    }

    private var totalAmount: Decimal {
        assetTokens.reduce(Decimal.zero) { sum, t in
            if t.role.isPositive { return sum + t.amount }
            if t.role.isBorrow { return sum - t.amount }
            return sum
        }
    }

    private var totalValue: Decimal {
        if let cgId = assetTokens.first?.asset?.coinGeckoId, let price = appState.prices[cgId] {
            return totalAmount * price
        }
        return assetTokens.reduce(Decimal.zero) { sum, t in
            if t.role.isPositive { return sum + t.usdValue }
            if t.role.isBorrow { return sum - t.usdValue }
            return sum
        }
    }

    private var accountCount: Int {
        Set(assetTokens.compactMap { $0.position?.account?.id }).count
    }

    /// Group by Position.chain (not Asset.upsertChain)
    private var byChain: [(String, Decimal, Decimal)] {
        var chains: [String: (amount: Decimal, value: Decimal)] = [:]
        for token in assetTokens where token.role.isPositive {
            let chainName = token.position?.chain?.rawValue.capitalized ?? "Off-chain"
            let val = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
                ?? token.usdValue
            chains[chainName, default: (0, 0)].amount += token.amount
            chains[chainName, default: (0, 0)].value += val
        }
        let total = chains.values.reduce(Decimal.zero) { $0 + $1.amount }
        return chains.map { (name, entry) in
            let share = total > 0 ? entry.amount / total : 0
            return (name, share, entry.value)
        }
        .sorted { $0.2 > $1.2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holdings Summary")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Accounts").font(.caption).foregroundStyle(.secondary)
                    Text("\(accountCount)").font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Total Amount").font(.caption).foregroundStyle(.secondary)
                    Text(totalAmount, format: .number.precision(.fractionLength(2...8)))
                        .font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Total Value").font(.caption).foregroundStyle(.secondary)
                    Text(totalValue, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                }
            }

            if !byChain.isEmpty {
                Text("On Networks").font(.subheadline.weight(.medium))
                ForEach(byChain, id: \.0) { (chain, share, value) in
                    HStack {
                        Text(chain)
                        Spacer()
                        Text(share, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                        Text(value, format: .currency(code: "USD"))
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.body)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Write AssetPositionsTable**

```swift
// Sources/Portu/Features/AssetDetail/AssetPositionsTable.swift
import SwiftUI
import SwiftData
import PortuCore

struct AssetPositionsTable: View {
    let assetId: UUID

    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    private struct PositionRow: Identifiable {
        let id: UUID
        let accountName: String
        let platformName: String
        let context: String // Staked/Idle/Lending/etc.
        let network: String
        let amount: Decimal
        let usdBalance: Decimal
    }

    private var rows: [PositionRow] {
        allTokens
            .filter { $0.asset?.id == assetId }
            .compactMap { token -> PositionRow? in
                guard let pos = token.position else { return nil }
                let value = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
                    ?? token.usdValue

                return PositionRow(
                    id: token.id,
                    accountName: pos.account?.name ?? "Unknown",
                    platformName: pos.protocolName ?? "Wallet",
                    context: pos.positionType.rawValue.capitalized,
                    network: pos.chain?.rawValue.capitalized ?? "Off-chain",
                    amount: token.amount,
                    usdBalance: value
                )
            }
            .sorted { $0.usdBalance > $1.usdBalance }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions").font(.headline)

            Table(rows) {
                TableColumn("Account") { row in Text(row.accountName) }
                    .width(min: 80, ideal: 120)
                TableColumn("Platform") { row in Text(row.platformName) }
                    .width(min: 80, ideal: 100)
                TableColumn("Context") { row in
                    Text(row.context)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                .width(min: 60, ideal: 80)
                TableColumn("Network") { row in Text(row.network) }
                    .width(min: 60, ideal: 80)
                TableColumn("Amount") { row in
                    Text(row.amount, format: .number.precision(.fractionLength(2...8)))
                }
                .width(min: 80, ideal: 100)
                TableColumn("USD Balance") { row in
                    Text(row.usdBalance, format: .currency(code: "USD"))
                }
                .width(min: 80, ideal: 100)
            }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/AssetHoldingsSummary.swift \
        Sources/Portu/Features/AssetDetail/AssetPositionsTable.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Asset Detail holdings summary and positions table

Holdings by network (Position.chain, not Asset.upsertChain).
Positions table with account, platform, context, network columns.
EOF
)"
```

---

### Task 4: Asset metadata sidebar

**Files:**
- Create: `Sources/Portu/Features/AssetDetail/AssetMetadataSidebar.swift`

- [ ] **Step 1: Write AssetMetadataSidebar**

```swift
// Sources/Portu/Features/AssetDetail/AssetMetadataSidebar.swift
import SwiftUI
import PortuCore

struct AssetMetadataSidebar: View {
    let asset: Asset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Logo placeholder
                if let logoURL = asset.logoURL, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "bitcoinsign.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                }

                // Name and symbol
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name).font(.title3.weight(.semibold))
                    Text(asset.symbol).font(.body).foregroundStyle(.secondary)
                }

                Divider()

                // Category
                LabeledContent("Category") {
                    Text(asset.category.rawValue.capitalized)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                // Verification
                LabeledContent("Verified") {
                    Image(systemName: asset.isVerified ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(asset.isVerified ? .green : .secondary)
                }

                // CoinGecko ID
                if let cgId = asset.coinGeckoId {
                    LabeledContent("CoinGecko") {
                        Text(cgId).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Explorer links note
                Text("Explorer links are per-position (varies by network), not per-asset.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/AssetDetail/AssetMetadataSidebar.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Asset Detail metadata sidebar
EOF
)"
```

---

### Task 5: Build and verify

- [ ] **Step 1: Build**

Run: `just build 2>&1 | tail -10`

- [ ] **Step 2: Commit any fixes**
