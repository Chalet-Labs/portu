# Phase 2: Navigation Shell & Overview View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the navigation shell (sidebar + detail switching) and the Overview dashboard — the reference implementation that validates the data model end-to-end.

**Architecture:** `NavigationSplitView` with sidebar sections. Overview is a two-column layout (main + inspector). All data comes from SwiftData `@Query` + `AppState` prices. Sync triggered from Overview's top bar.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Swift Charts

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Navigation, Views §1)

**Depends on:** Plans 01 + 02 (Data Models, Providers, SyncEngine) must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/Overview/OverviewView.swift`
- `Sources/Portu/Features/Overview/OverviewTopBar.swift`
- `Sources/Portu/Features/Overview/PortfolioValueChart.swift`
- `Sources/Portu/Features/Overview/OverviewSummaryCards.swift`
- `Sources/Portu/Features/Overview/OverviewPositionTabs.swift`
- `Sources/Portu/Features/Overview/InspectorPanel.swift`
- `Sources/Portu/Features/Overview/TopAssetsDonut.swift`
- `Sources/Portu/Features/Overview/PriceWatchlist.swift`

### Modify
- `Sources/Portu/Features/Sidebar/SidebarView.swift` — full rework for new sections
- `Sources/Portu/App/ContentView.swift` — switch on new SidebarSection
- `Sources/Portu/App/StatusBarView.swift` — update for SyncStatus

### Delete
- `Sources/Portu/Features/Portfolio/PortfolioView.swift` — replaced by OverviewView
- `Sources/Portu/Features/Portfolio/HoldingRow.swift` — replaced by new position row
- `Sources/Portu/Features/Portfolio/SummaryCards.swift` — replaced by Overview version

---

### Task 1: Rework SidebarView

**Files:**
- Modify: `Sources/Portu/Features/Sidebar/SidebarView.swift`

- [ ] **Step 1: Rewrite SidebarView**

```swift
// Sources/Portu/Features/Sidebar/SidebarView.swift
import SwiftUI
import SwiftData
import PortuCore

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSection) {
            Section("PORTU") {
                Label("Overview", systemImage: "chart.pie")
                    .tag(SidebarSection.overview)
                Label("Exposure", systemImage: "chart.bar.xaxis")
                    .tag(SidebarSection.exposure)
                Label("Performance", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(SidebarSection.performance)
            }

            Section("PORTFOLIO") {
                Label("All Assets", systemImage: "bitcoinsign.circle")
                    .tag(SidebarSection.allAssets)
                Label("All Positions", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSection.allPositions)
            }

            Section("MANAGEMENT") {
                Label("Accounts", systemImage: "person.2")
                    .tag(SidebarSection.accounts)
            }

            Section {
                Label("Strategies", systemImage: "lightbulb")
                    .foregroundStyle(.tertiary)
            } header: {
                Text("") // Divider spacing
            }
            .disabled(true)
        }
        .listStyle(.sidebar)
        .navigationTitle("Portu")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Sidebar/SidebarView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: rework SidebarView with all navigation sections

Overview, Exposure, Performance | All Assets, All Positions |
Accounts | Strategies (disabled placeholder).
EOF
)"
```

---

### Task 2: Update ContentView for section switching

**Files:**
- Modify: `Sources/Portu/App/ContentView.swift`

- [ ] **Step 1: Rewrite ContentView**

```swift
// Sources/Portu/App/ContentView.swift
import SwiftUI
import SwiftData
import PortuCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
                .navigationDestination(for: UUID.self) { assetId in
                    // Asset Detail push destination (Plan 09)
                    Text("Asset Detail: \(assetId)")
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewView()
        case .exposure:
            Text("Exposure View") // Plan 07
        case .performance:
            Text("Performance View") // Plan 06
        case .allAssets:
            Text("All Assets View") // Plan 04
        case .allPositions:
            Text("All Positions View") // Plan 05
        case .accounts:
            Text("Accounts View") // Plan 08
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: update ContentView for new SidebarSection routing

Switches detail view based on selected section. Placeholder text
for views implemented in Phase 3.
EOF
)"
```

---

### Task 3: Update StatusBarView for SyncStatus

**Files:**
- Modify: `Sources/Portu/App/StatusBarView.swift`

- [ ] **Step 1: Update StatusBarView**

```swift
// Sources/Portu/App/StatusBarView.swift
import SwiftUI
import PortuCore

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            if appState.storeIsEphemeral {
                Label("Database error — using temporary storage", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            syncStatusLabel

            Spacer()

            if let lastUpdate = appState.lastPriceUpdate {
                Text("Updated \(lastUpdate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("CoinGecko")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var syncStatusLabel: some View {
        switch appState.syncStatus {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .syncing(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 60)
                Text("Syncing…")
                    .font(.caption)
            }
        case .completedWithErrors(let failed):
            Label("\(failed.count) account(s) failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Failed: \(failed.joined(separator: ", "))")
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/App/StatusBarView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: update StatusBarView for SyncStatus display
EOF
)"
```

---

### Task 4: Delete obsolete Portfolio view files

**Files:**
- Delete: `Sources/Portu/Features/Portfolio/PortfolioView.swift`
- Delete: `Sources/Portu/Features/Portfolio/HoldingRow.swift`
- Delete: `Sources/Portu/Features/Portfolio/SummaryCards.swift`

- [ ] **Step 1: Delete files**

```bash
rm -rf Sources/Portu/Features/Portfolio/
```

- [ ] **Step 2: Commit**

```bash
git add -A Sources/Portu/Features/Portfolio/
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: remove obsolete Portfolio views (replaced by Overview)
EOF
)"
```

---

### Task 5: OverviewView shell + top bar

**Files:**
- Create: `Sources/Portu/Features/Overview/OverviewView.swift`
- Create: `Sources/Portu/Features/Overview/OverviewTopBar.swift`

- [ ] **Step 1: Create Overview directory**

```bash
mkdir -p Sources/Portu/Features/Overview
```

- [ ] **Step 2: Write OverviewTopBar**

```swift
// Sources/Portu/Features/Overview/OverviewTopBar.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    let onSync: () -> Void

    private var totalValue: Decimal {
        positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
    }

    private var change24h: Decimal {
        // Sum: token.amount × priceChange24h for each token, sign-adjusted by role
        var total: Decimal = 0
        for pos in positions {
            for token in pos.tokens {
                guard let asset = token.asset,
                      let cgId = asset.coinGeckoId,
                      let price = appState.prices[cgId],
                      let changePct = appState.priceChanges24h[cgId] else { continue }

                let contribution = token.amount * price * changePct
                if token.role.isPositive {
                    total += contribution
                } else if token.role.isBorrow {
                    total -= contribution
                }
                // reward: excluded
            }
        }
        return total
    }

    private var changePct: Decimal {
        let prev = totalValue - change24h
        guard prev != 0 else { return 0 }
        return change24h / prev
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Total value
            VStack(alignment: .leading, spacing: 2) {
                Text("Portfolio Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalValue, format: .currency(code: "USD"))
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }

            // 24h change
            VStack(alignment: .leading, spacing: 2) {
                Text("24h Change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(PortuTheme.changeColor(for: change24h))
                    Text(change24h, format: .currency(code: "USD"))
                        .foregroundStyle(PortuTheme.changeColor(for: change24h))
                    Text("(\(changePct, format: .percent.precision(.fractionLength(2))))")
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }

            Spacer()

            // Last synced + Sync button
            if case .syncing = appState.syncStatus {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: onSync) {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appState.syncStatus == .syncing(progress: 0))
            }
        }
        .padding()
    }
}
```

- [ ] **Step 3: Write OverviewView shell**

```swift
// Sources/Portu/Features/Overview/OverviewView.swift
import SwiftUI
import SwiftData
import PortuCore

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine

    var body: some View {
        HSplitView {
            // Main content (left, flex: 3)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OverviewTopBar {
                        Task { await syncEngine.sync() }
                    }

                    PortfolioValueChart()

                    OverviewSummaryCards()

                    OverviewPositionTabs()
                }
                .padding()
            }
            .frame(minWidth: 500)
            .layoutPriority(3)

            // Inspector panel (right, flex: 1, collapsible)
            InspectorPanel()
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
                .layoutPriority(1)
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/Overview/
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add OverviewView shell with top bar and 24h change calculation

Two-column layout with main content + inspector panel. Top bar shows
total value, 24h change (role-sign-adjusted), and sync button.
EOF
)"
```

---

### Task 6: Portfolio value chart

**Files:**
- Create: `Sources/Portu/Features/Overview/PortfolioValueChart.swift`

- [ ] **Step 1: Write PortfolioValueChart**

```swift
// Sources/Portu/Features/Overview/PortfolioValueChart.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

struct PortfolioValueChart: View {
    @Query(sort: \PortfolioSnapshot.timestamp)
    private var snapshots: [PortfolioSnapshot]

    @State private var selectedRange: TimeRange = .oneMonth

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case oneYear = "1Y"
        case ytd = "YTD"

        var startDate: Date {
            let cal = Calendar.current
            let now = Date.now
            return switch self {
            case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
            case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
            case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
            case .ytd: cal.date(from: cal.dateComponents([.year], from: now))!
            }
        }
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        let start = selectedRange.startDate
        return snapshots.filter { $0.timestamp >= start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Time range picker
            Picker("Range", selection: $selectedRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            if filteredSnapshots.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see portfolio history")
                )
                .frame(height: 200)
            } else {
                Chart(filteredSnapshots, id: \.id) { snapshot in
                    AreaMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Value", snapshot.totalValue)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Value", snapshot.totalValue)
                    )
                    .foregroundStyle(Color.accentColor)

                    // Partial snapshot indicator
                    if snapshot.isPartial {
                        PointMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.totalValue)
                        )
                        .symbolSize(20)
                        .foregroundStyle(.orange.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 250)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Overview/PortfolioValueChart.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add PortfolioValueChart with time range selector

Swift Charts AreaMark from PortfolioSnapshot data. Partial snapshots
indicated with orange dot. 1W/1M/3M/1Y/YTD range picker.
EOF
)"
```

---

### Task 7: Summary cards (Idle / Deployed / Futures)

**Files:**
- Create: `Sources/Portu/Features/Overview/OverviewSummaryCards.swift`

- [ ] **Step 1: Write OverviewSummaryCards**

```swift
// Sources/Portu/Features/Overview/OverviewSummaryCards.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct OverviewSummaryCards: View {
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    private var idleBreakdown: [(String, Decimal)] {
        let idle = positions.filter { $0.positionType == .idle }
        var stablesFiat: Decimal = 0
        var majors: Decimal = 0
        var tokens: Decimal = 0

        for pos in idle {
            for token in pos.tokens where token.role.isPositive {
                switch token.asset?.category {
                case .stablecoin, .fiat: stablesFiat += token.usdValue
                case .major: majors += token.usdValue
                default: tokens += token.usdValue
                }
            }
        }
        return [
            ("Stablecoins & Fiat", stablesFiat),
            ("Majors", majors),
            ("Tokens & Memes", tokens),
        ]
    }

    private var deployedBreakdown: [(String, Decimal)] {
        let deployed = positions.filter {
            [.lending, .staking, .farming, .liquidityPool].contains($0.positionType)
        }
        var lending: Decimal = 0
        var staked: Decimal = 0
        var yield: Decimal = 0

        for pos in deployed {
            let posVal = pos.tokens.filter { $0.role.isPositive }.reduce(Decimal.zero) { $0 + $1.usdValue }
            switch pos.positionType {
            case .lending: lending += posVal
            case .staking: staked += posVal
            case .farming, .liquidityPool: yield += posVal
            default: break
            }
        }
        return [
            ("Lending", lending),
            ("Staked", staked),
            ("Yield", yield),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            summaryCard(title: "Idle", items: idleBreakdown)
            summaryCard(title: "Deployed", items: deployedBreakdown)
            summaryCard(title: "Futures", items: []) // Future work
        }
    }

    private func summaryCard(title: String, items: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            let total = items.reduce(Decimal.zero) { $0 + $1.1 }
            Text(total, format: .currency(code: "USD"))
                .font(.title3.weight(.semibold))

            if items.isEmpty {
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items, id: \.0) { label, value in
                    HStack {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(value, format: .currency(code: "USD")).font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Overview/OverviewSummaryCards.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Overview summary cards (Idle/Deployed/Futures)

Idle grouped by Stablecoins & Fiat, Majors, Tokens.
Deployed grouped by Lending, Staked, Yield. Futures placeholder.
EOF
)"
```

---

### Task 8: Tabbed positions list

**Files:**
- Create: `Sources/Portu/Features/Overview/OverviewPositionTabs.swift`

Tabs: Key Changes, Idle Stables, Idle Majors, Borrowing. All show PositionToken-level rows.

- [ ] **Step 1: Write OverviewPositionTabs**

```swift
// Sources/Portu/Features/Overview/OverviewPositionTabs.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct OverviewPositionTabs: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    @State private var selectedTab: OverviewTab = .keyChanges

    enum OverviewTab: String, CaseIterable {
        case keyChanges = "Key Changes"
        case idleStables = "Idle Stables"
        case idleMajors = "Idle Majors"
        case borrowing = "Borrowing"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(OverviewTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .keyChanges:
                tokenTable(tokens: keyChangeTokens)
            case .idleStables:
                tokenTable(tokens: idleStableTokens)
            case .idleMajors:
                tokenTable(tokens: idleMajorTokens)
            case .borrowing:
                borrowingView
            }
        }
    }

    // MARK: - Token filtering

    private var allActiveTokens: [(PositionToken, Position)] {
        positions.flatMap { pos in pos.tokens.map { ($0, pos) } }
    }

    private var keyChangeTokens: [(PositionToken, Position)] {
        // Tokens with largest 24h USD change (absolute value)
        allActiveTokens
            .filter { $0.0.role.isPositive }
            .sorted { abs(tokenChange24h($0.0)) > abs(tokenChange24h($1.0)) }
            .prefix(20)
            .map { ($0.0, $0.1) }
    }

    private var idleStableTokens: [(PositionToken, Position)] {
        allActiveTokens
            .filter { $0.1.positionType == .idle && $0.0.asset?.category == .stablecoin && $0.0.role.isPositive }
    }

    private var idleMajorTokens: [(PositionToken, Position)] {
        allActiveTokens
            .filter { $0.1.positionType == .idle && $0.0.asset?.category == .major && $0.0.role.isPositive }
    }

    private func tokenChange24h(_ token: PositionToken) -> Decimal {
        guard let cgId = token.asset?.coinGeckoId,
              let price = appState.prices[cgId],
              let changePct = appState.priceChanges24h[cgId] else { return 0 }
        return token.amount * price * changePct
    }

    // MARK: - Token table (flat rows)

    private func tokenTable(tokens: [(PositionToken, Position)]) -> some View {
        Table(of: TokenRowData.self) {
            TableColumn("Asset") { row in
                Text(row.symbol).fontWeight(.medium)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Network / Account") { row in
                VStack(alignment: .leading) {
                    if let chain = row.chain { Text(chain.rawValue.capitalized).font(.caption) }
                    Text(row.accountName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("Amount") { row in
                Text(row.amount, format: .number.precision(.fractionLength(2...6)))
            }
            .width(min: 80, ideal: 100)

            TableColumn("Price") { row in
                Text(row.price, format: .currency(code: "USD"))
            }
            .width(min: 60, ideal: 80)

            TableColumn("Value") { row in
                Text(row.value, format: .currency(code: "USD"))
            }
            .width(min: 80, ideal: 100)
        } rows: {
            ForEach(tokens.map { makeTokenRowData($0.0, position: $0.1) }, id: \.id) { row in
                TableRow(row)
            }
        }
    }

    // MARK: - Borrowing view (grouped by protocol)

    @ViewBuilder
    private var borrowingView: some View {
        let borrowPositions = positions.filter { pos in
            pos.tokens.contains { $0.role.isBorrow }
        }
        if borrowPositions.isEmpty {
            ContentUnavailableView("No Borrowing", systemImage: "arrow.down.circle",
                                   description: Text("No active borrow positions"))
        } else {
            ForEach(borrowPositions, id: \.id) { pos in
                VStack(alignment: .leading, spacing: 4) {
                    // Section header
                    HStack {
                        Text(pos.protocolName ?? "Unknown Protocol")
                            .font(.headline)
                        if let chain = pos.chain {
                            Text(chain.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if let hf = pos.healthFactor {
                            Text("HF: \(hf, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundStyle(hf < 1.2 ? .red : hf < 1.5 ? .orange : .green)
                        }
                    }

                    // Token rows
                    ForEach(pos.tokens, id: \.id) { token in
                        HStack {
                            Text(token.role == .borrow ? "← Borrow" : "→ Supply")
                                .font(.caption)
                                .foregroundStyle(token.role.isBorrow ? .orange : .green)
                            Text(token.asset?.symbol ?? "???")
                            Spacer()
                            Text(token.amount, format: .number.precision(.fractionLength(2...6)))
                            Text(tokenValue(token), format: .currency(code: "USD"))
                                .frame(width: 100, alignment: .trailing)
                        }
                        .font(.body)
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Helpers

    private struct TokenRowData: Identifiable {
        let id: UUID
        let symbol: String
        let chain: Chain?
        let accountName: String
        let amount: Decimal
        let price: Decimal
        let value: Decimal
    }

    private func makeTokenRowData(_ token: PositionToken, position: Position) -> TokenRowData {
        let price = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }
            ?? (token.amount > 0 ? token.usdValue / token.amount : 0)
        let value = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue

        return TokenRowData(
            id: token.id,
            symbol: token.asset?.symbol ?? "???",
            chain: position.chain,
            accountName: position.account?.name ?? "",
            amount: token.amount,
            price: price,
            value: value
        )
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Overview/OverviewPositionTabs.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Overview tabbed positions list

Key Changes, Idle Stables, Idle Majors (flat token rows), Borrowing
(grouped by protocol with health factor). PositionToken-level display
using sign convention display rules.
EOF
)"
```

---

### Task 9: Inspector panel (Top Assets donut + Price watchlist)

**Files:**
- Create: `Sources/Portu/Features/Overview/InspectorPanel.swift`
- Create: `Sources/Portu/Features/Overview/TopAssetsDonut.swift`
- Create: `Sources/Portu/Features/Overview/PriceWatchlist.swift`

- [ ] **Step 1: Write TopAssetsDonut**

```swift
// Sources/Portu/Features/Overview/TopAssetsDonut.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

struct TopAssetsDonut: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var tokens: [PositionToken]

    @State private var groupByCategory = true

    private struct SliceData: Identifiable {
        let id = UUID()
        let label: String
        let value: Decimal
        let color: Color
    }

    private var slices: [SliceData] {
        if groupByCategory {
            // Group by AssetCategory
            var byCategory: [AssetCategory: Decimal] = [:]
            for token in tokens where token.role.isPositive {
                let cat = token.asset?.category ?? .other
                let value = tokenUSDValue(token)
                byCategory[cat, default: 0] += value
            }
            return byCategory
                .sorted { $0.value > $1.value }
                .prefix(8)
                .enumerated()
                .map { SliceData(label: $0.element.key.rawValue.capitalized,
                                  value: $0.element.value,
                                  color: chartColor(index: $0.offset)) }
        } else {
            // Group by Asset
            var byAsset: [String: Decimal] = [:]
            for token in tokens where token.role.isPositive {
                let symbol = token.asset?.symbol ?? "???"
                byAsset[symbol, default: 0] += tokenUSDValue(token)
            }
            return byAsset
                .sorted { $0.value > $1.value }
                .prefix(8)
                .enumerated()
                .map { SliceData(label: $0.element.key,
                                  value: $0.element.value,
                                  color: chartColor(index: $0.offset)) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top Assets")
                    .font(.headline)
                Spacer()
                Picker("Group", selection: $groupByCategory) {
                    Text("Category").tag(true)
                    Text("Asset").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if slices.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Value", slice.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 1
                    )
                    .foregroundStyle(slice.color)
                    .annotation(position: .overlay) {
                        Text(slice.label)
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 180)

                // Legend
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label).font(.caption)
                        Spacer()
                        Text(slice.value, format: .currency(code: "USD")).font(.caption)
                    }
                }
            }

            Button("See all →") {
                // Navigate to All Assets — handled via appState.selectedSection
            }
            .font(.caption)
        }
    }

    private func tokenUSDValue(_ token: PositionToken) -> Decimal {
        token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue
    }

    private func chartColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .yellow, .cyan, .red]
        return colors[index % colors.count]
    }
}
```

- [ ] **Step 2: Write PriceWatchlist**

```swift
// Sources/Portu/Features/Overview/PriceWatchlist.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct PriceWatchlist: View {
    @Environment(AppState.self) private var appState
    @Query private var assets: [Asset]

    /// Top assets by portfolio value (those with coinGeckoId for live pricing)
    private var watchlistAssets: [Asset] {
        assets
            .filter { $0.coinGeckoId != nil }
            .sorted { (appState.prices[$0.coinGeckoId!] ?? 0) > (appState.prices[$1.coinGeckoId!] ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prices")
                .font(.headline)

            ForEach(watchlistAssets, id: \.id) { asset in
                HStack {
                    Text(asset.symbol)
                        .fontWeight(.medium)
                    Spacer()

                    if let cgId = asset.coinGeckoId, let price = appState.prices[cgId] {
                        VStack(alignment: .trailing) {
                            Text(price, format: .currency(code: "USD"))
                                .font(.body)
                            if let change = appState.priceChanges24h[cgId] {
                                HStack(spacing: 2) {
                                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    Text(change, format: .percent.precision(.fractionLength(2)))
                                }
                                .font(.caption)
                                .foregroundStyle(PortuTheme.changeColor(for: change))
                            }
                        }
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                Divider()
            }
        }
    }
}
```

- [ ] **Step 3: Write InspectorPanel**

```swift
// Sources/Portu/Features/Overview/InspectorPanel.swift
import SwiftUI

struct InspectorPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TopAssetsDonut()
                Divider()
                PriceWatchlist()
            }
            .padding()
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/Overview/InspectorPanel.swift \
        Sources/Portu/Features/Overview/TopAssetsDonut.swift \
        Sources/Portu/Features/Overview/PriceWatchlist.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Overview inspector panel with donut chart and price watchlist

TopAssetsDonut uses SectorMark with category/asset toggle.
PriceWatchlist shows top portfolio assets with live prices and 24h change.
EOF
)"
```

---

### Task 10: Build and verify

- [ ] **Step 1: Build the full app**

Run: `just build 2>&1 | tail -20`
Expected: SUCCESS

- [ ] **Step 2: Run tests**

Run: `just test-packages && just test 2>&1 | tail -30`

- [ ] **Step 3: Fix any issues and commit**

```bash
git add -A
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
fix: resolve compilation issues in Phase 2 views
EOF
)"
```
