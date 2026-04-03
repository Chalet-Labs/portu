# Phase 3: Performance View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Performance view with 3 chart modes (Value, Assets, PnL), account filter, time range selector, and bottom panels.

**Architecture:** Three snapshot tiers power this view: PortfolioSnapshot → Value mode (all accounts), AccountSnapshot → Value mode (account-filtered), AssetSnapshot → Assets mode (category breakdown). PnL is computed as daily deltas.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Swift Charts

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Views §4)

**Depends on:** Plans 01-03 must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/Performance/PerformanceView.swift`
- `Sources/Portu/Features/Performance/ValueChartMode.swift`
- `Sources/Portu/Features/Performance/AssetsChartMode.swift`
- `Sources/Portu/Features/Performance/PnLChartMode.swift`
- `Sources/Portu/Features/Performance/PerformanceBottomPanel.swift`

---

### Task 1: PerformanceView shell with controls

**Files:**
- Create: `Sources/Portu/Features/Performance/PerformanceView.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/Portu/Features/Performance
```

- [ ] **Step 2: Write PerformanceView**

```swift
// Sources/Portu/Features/Performance/PerformanceView.swift
import SwiftUI
import SwiftData
import PortuCore

struct PerformanceView: View {
    @Query private var accounts: [Account]

    @State private var selectedAccountId: UUID? = nil  // nil = all accounts
    @State private var selectedRange: TimeRange = .oneMonth
    @State private var chartMode: ChartMode = .value

    enum ChartMode: String, CaseIterable {
        case value = "Value"
        case assets = "Assets"
        case pnl = "PnL"
    }

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W", oneMonth = "1M", threeMonths = "3M"
        case oneYear = "1Y", ytd = "YTD", custom = "Custom"

        var startDate: Date {
            let cal = Calendar.current
            let now = Date.now
            return switch self {
            case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
            case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
            case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
            case .ytd: cal.date(from: cal.dateComponents([.year], from: now))!
            case .custom: cal.date(byAdding: .month, value: -1, to: now)! // Default; overridden by date picker
            }
        }
    }

    // When chartMode == .custom, show date pickers for custom start/end
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var customEndDate = Date.now

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack {
                // Account filter
                Picker("Account", selection: $selectedAccountId) {
                    Text("All Accounts").tag(nil as UUID?)
                    ForEach(accounts.filter(\.isActive), id: \.id) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }
                .frame(width: 200)

                Spacer()

                // Time range
                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                // Chart mode
                Picker("Mode", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()

            // Chart
            switch chartMode {
            case .value:
                ValueChartMode(
                    accountId: selectedAccountId,
                    startDate: selectedRange.startDate
                )
            case .assets:
                AssetsChartMode(
                    accountId: selectedAccountId,
                    startDate: selectedRange.startDate
                )
            case .pnl:
                PnLChartMode(
                    accountId: selectedAccountId,
                    startDate: selectedRange.startDate
                )
            }

            Divider()

            // Bottom panels
            PerformanceBottomPanel(
                accountId: selectedAccountId,
                startDate: selectedRange.startDate
            )
        }
        .navigationTitle("Performance")
    }
}
```

- [ ] **Step 3: Wire into ContentView**

```swift
case .performance:
    PerformanceView()
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/Performance/PerformanceView.swift Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add PerformanceView shell with account filter, time range, chart mode
EOF
)"
```

---

### Task 2: Value chart mode

**Files:**
- Create: `Sources/Portu/Features/Performance/ValueChartMode.swift`

AreaMark from PortfolioSnapshot (all) or AccountSnapshot (filtered).

- [ ] **Step 1: Write ValueChartMode**

```swift
// Sources/Portu/Features/Performance/ValueChartMode.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

struct ValueChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \PortfolioSnapshot.timestamp)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @Query(sort: \AccountSnapshot.timestamp)
    private var accountSnapshots: [AccountSnapshot]

    private var dataPoints: [(Date, Decimal, Bool)] {
        if let accountId {
            return accountSnapshots
                .filter { $0.accountId == accountId && $0.timestamp >= startDate }
                .map { ($0.timestamp, $0.totalValue, !$0.isFresh) }
        } else {
            return portfolioSnapshots
                .filter { $0.timestamp >= startDate }
                .map { ($0.timestamp, $0.totalValue, $0.isPartial) }
        }
    }

    var body: some View {
        if dataPoints.isEmpty {
            ContentUnavailableView("No Performance Data", systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Sync your accounts to track portfolio performance"))
                .frame(height: 300)
        } else {
            Chart {
                ForEach(dataPoints, id: \.0) { (date, value, isPartial) in
                    AreaMark(x: .value("Date", date), y: .value("Value", value))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Color.accentColor.opacity(0.3), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("Date", date), y: .value("Value", value))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(isPartial ? StrokeStyle(lineWidth: 2, dash: [5, 3]) : StrokeStyle(lineWidth: 2))
                }
            }
            .chartYAxis {
                AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
            }
            .frame(height: 300)
            .padding()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Performance/ValueChartMode.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Value chart mode with partial snapshot indicators

AreaMark from PortfolioSnapshot or AccountSnapshot. Partial/stale
snapshots shown with dashed line.
EOF
)"
```

---

### Task 3: Assets chart mode (stacked area by category)

**Files:**
- Create: `Sources/Portu/Features/Performance/AssetsChartMode.swift`

Stacked AreaMark from AssetSnapshot grouped by category.

- [ ] **Step 1: Write AssetsChartMode**

```swift
// Sources/Portu/Features/Performance/AssetsChartMode.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

struct AssetsChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp)
    private var snapshots: [AssetSnapshot]

    @State private var disabledCategories: Set<AssetCategory> = []

    private var filtered: [AssetSnapshot] {
        snapshots.filter { snap in
            snap.timestamp >= startDate &&
            !disabledCategories.contains(snap.category) &&
            (accountId == nil || snap.accountId == accountId)
        }
    }

    /// Group by timestamp + category, sum usdValue
    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let value: Decimal
    }

    private var chartData: [ChartPoint] {
        var grouped: [Date: [AssetCategory: Decimal]] = [:]
        for snap in filtered {
            // Bucket by day for cleaner charting
            let day = Calendar.current.startOfDay(for: snap.timestamp)
            grouped[day, default: [:]][snap.category, default: 0] += snap.usdValue
        }
        return grouped.flatMap { (date, categories) in
            categories.map { ChartPoint(date: date, category: $0.key.rawValue.capitalized, value: $0.value) }
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 8) {
            if chartData.isEmpty {
                ContentUnavailableView("No Asset Data", systemImage: "chart.bar.xaxis",
                                       description: Text("Sync to see asset category breakdown"))
                    .frame(height: 300)
            } else {
                Chart(chartData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Category", point.category))
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 300)
                .padding()
            }

            // Category toggle chips
            HStack(spacing: 8) {
                ForEach(AssetCategory.allCases, id: \.self) { cat in
                    Button {
                        if disabledCategories.contains(cat) {
                            disabledCategories.remove(cat)
                        } else {
                            disabledCategories.insert(cat)
                        }
                    } label: {
                        Text(cat.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(disabledCategories.contains(cat) ? .quaternary : .accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Performance/AssetsChartMode.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Assets chart mode with stacked area by category

Category filter chips toggle categories on/off. Account filter
supported via AssetSnapshot.accountId.
EOF
)"
```

---

### Task 4: PnL chart mode

**Files:**
- Create: `Sources/Portu/Features/Performance/PnLChartMode.swift`

BarMark for daily PnL. Simple mark-to-market (no cost-basis).

- [ ] **Step 1: Write PnLChartMode**

```swift
// Sources/Portu/Features/Performance/PnLChartMode.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

struct PnLChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnaps: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnaps: [AccountSnapshot]

    @State private var showCumulative = false

    private struct PnLBar: Identifiable {
        let id = UUID()
        let date: Date
        let pnl: Decimal
        let cumulative: Decimal
    }

    private var bars: [PnLBar] {
        // Get daily totals
        let dailyValues: [(Date, Decimal)]
        if let accountId {
            let filtered = accountSnaps.filter { $0.accountId == accountId && $0.timestamp >= startDate }
            dailyValues = lastPerDay(filtered.map { ($0.timestamp, $0.totalValue) })
        } else {
            let filtered = portfolioSnaps.filter { $0.timestamp >= startDate }
            dailyValues = lastPerDay(filtered.map { ($0.timestamp, $0.totalValue) })
        }

        guard dailyValues.count >= 2 else { return [] }

        var result: [PnLBar] = []
        var cumulative: Decimal = 0
        for i in 1..<dailyValues.count {
            let pnl = dailyValues[i].1 - dailyValues[i-1].1
            cumulative += pnl
            result.append(PnLBar(date: dailyValues[i].0, pnl: pnl, cumulative: cumulative))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            if bars.isEmpty {
                ContentUnavailableView("Insufficient Data", systemImage: "chart.bar",
                                       description: Text("Need at least 2 days of data for PnL"))
                    .frame(height: 300)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: .day),
                        y: .value("PnL", bar.pnl)
                    )
                    .foregroundStyle(bar.pnl >= 0 ? Color.green : Color.red)

                    if showCumulative {
                        LineMark(
                            x: .value("Date", bar.date, unit: .day),
                            y: .value("Cumulative", bar.cumulative)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 300)
                .padding()
            }

            Toggle("Show Cumulative", isOn: $showCumulative)
                .padding(.horizontal)
        }
    }

    /// Keep last snapshot per day
    private func lastPerDay(_ values: [(Date, Decimal)]) -> [(Date, Decimal)] {
        let cal = Calendar.current
        var byDay: [DateComponents: (Date, Decimal)] = [:]
        for (date, value) in values {
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            if let existing = byDay[comps] {
                if date > existing.0 { byDay[comps] = (date, value) }
            } else {
                byDay[comps] = (date, value)
            }
        }
        return byDay.values.sorted { $0.0 < $1.0 }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Performance/PnLChartMode.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add PnL chart mode with daily bars and cumulative overlay

Mark-to-market PnL from daily snapshot deltas. Green/red bars
with optional cumulative LineMark overlay.
EOF
)"
```

---

### Task 5: Bottom panels (category breakdown + asset prices)

**Files:**
- Create: `Sources/Portu/Features/Performance/PerformanceBottomPanel.swift`

- [ ] **Step 1: Write PerformanceBottomPanel**

```swift
// Sources/Portu/Features/Performance/PerformanceBottomPanel.swift
import SwiftUI
import SwiftData
import PortuCore

struct PerformanceBottomPanel: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp) private var snapshots: [AssetSnapshot]

    /// Category breakdown: compare start vs end usdValue per category
    private var categoryChanges: [(String, Decimal, Decimal, Decimal)] {
        let filtered = snapshots.filter { s in
            s.timestamp >= startDate && (accountId == nil || s.accountId == accountId)
        }
        guard !filtered.isEmpty else { return [] }

        let sorted = filtered.sorted { $0.timestamp < $1.timestamp }
        let firstDay = Calendar.current.startOfDay(for: sorted.first!.timestamp)
        let lastDay = Calendar.current.startOfDay(for: sorted.last!.timestamp)

        var startValues: [AssetCategory: Decimal] = [:]
        var endValues: [AssetCategory: Decimal] = [:]

        for s in sorted {
            let day = Calendar.current.startOfDay(for: s.timestamp)
            if day == firstDay { startValues[s.category, default: 0] += s.usdValue }
            if day == lastDay { endValues[s.category, default: 0] += s.usdValue }
        }

        return AssetCategory.allCases.compactMap { cat in
            let start = startValues[cat, default: 0]
            let end = endValues[cat, default: 0]
            guard start > 0 || end > 0 else { return nil }
            let change = start > 0 ? (end - start) / start : 0
            return (cat.rawValue.capitalized, start, end, change)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Asset categories panel
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Categories").font(.headline)
                ForEach(categoryChanges, id: \.0) { (name, start, end, change) in
                    HStack {
                        Text(name).frame(width: 100, alignment: .leading)
                        Text(start, format: .currency(code: "USD")).frame(width: 100)
                        Text("→").foregroundStyle(.secondary)
                        Text(end, format: .currency(code: "USD")).frame(width: 100)
                        Text(change, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(change >= 0 ? .green : .red)
                            .frame(width: 60)
                    }
                    .font(.caption)
                }
            }

            Divider()

            // Asset prices panel
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Prices").font(.headline)
                Text("Top assets with period price change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // TODO: Populate from PriceService historical data
            }
        }
        .padding()
        .frame(height: 200)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Performance/PerformanceBottomPanel.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Performance bottom panels with category breakdown
EOF
)"
```

---

### Task 6: Build and verify

- [ ] **Step 1: Build**

Run: `just build 2>&1 | tail -10`

- [ ] **Step 2: Commit any fixes**
