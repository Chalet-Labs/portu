import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

enum PerformanceChartMode: String, CaseIterable, Equatable, Hashable {
    case value = "Value"
    case assets = "Assets"
    case pnl = "PnL"
}

/// PnL bar data for chart display.
struct PnLBar: Identifiable, Equatable {
    let id: Date
    let date: Date
    let pnl: Decimal
    let cumulative: Decimal
}

/// Category change data for the bottom panel.
struct CategoryChange: Identifiable, Equatable {
    var id: String {
        name
    }

    let name: String
    let startValue: Decimal
    let endValue: Decimal
    let percentChange: Decimal
}

/// Lightweight input for category change and chart aggregation.
struct CategorySnapshotEntry: Equatable {
    let accountId: UUID
    let assetId: UUID
    let timestamp: Date
    let category: AssetCategory
    let usdValue: Decimal
}

/// Aggregated category chart data point (one per day per category).
struct CategoryChartPoint: Equatable {
    let date: Date
    let category: String
    let value: Decimal
}

// MARK: - PerformanceFeature

@Reducer
struct PerformanceFeature {
    @ObservableState
    struct State: Equatable {
        var selectedAccountId: UUID?
        var selectedRange: ChartTimeRange = .oneMonth
        var chartMode: PerformanceChartMode = .value
        var disabledCategories: Set<AssetCategory> = []
        var showCumulative: Bool = false
    }

    enum Action: Equatable {
        case accountSelected(UUID?)
        case timeRangeChanged(ChartTimeRange)
        case chartModeChanged(PerformanceChartMode)
        case categoryToggled(AssetCategory)
        case showCumulativeToggled
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .accountSelected(id):
                state.selectedAccountId = id
                return .none

            case let .timeRangeChanged(range):
                state.selectedRange = range
                return .none

            case let .chartModeChanged(mode):
                state.chartMode = mode
                return .none

            case let .categoryToggled(category):
                if state.disabledCategories.contains(category) {
                    state.disabledCategories.remove(category)
                } else {
                    state.disabledCategories.insert(category)
                }
                return .none

            case .showCumulativeToggled:
                state.showCumulative.toggle()
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Keep only the last value per calendar day, sorted ascending.
    static func lastPerDay(_ values: [(Date, Decimal)]) -> [(Date, Decimal)] {
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

    /// Compute daily PnL bars with cumulative totals.
    static func computePnLBars(from dailyValues: [(Date, Decimal)]) -> [PnLBar] {
        guard dailyValues.count >= 2 else { return [] }
        var result: [PnLBar] = []
        var cumulative: Decimal = 0
        for i in 1 ..< dailyValues.count {
            let pnl = dailyValues[i].1 - dailyValues[i - 1].1
            cumulative += pnl
            result.append(PnLBar(
                id: dailyValues[i].0,
                date: dailyValues[i].0,
                pnl: pnl,
                cumulative: cumulative))
        }
        return result
    }

    /// Aggregate category snapshots by day — one chart point per (day, category).
    /// Deduplicates by taking the latest snapshot per (day, accountId, assetId, category),
    /// then sums across unique (accountId, assetId) combinations per (day, category).
    static func aggregateCategorySnapshots(
        entries: [CategorySnapshotEntry]) -> [CategoryChartPoint] {
        let cal = Calendar.current

        // Step 1: Dedup — for each (day, accountId, assetId, category), keep the latest timestamp.
        struct DedupKey: Hashable {
            let day: Date
            let accountId: UUID
            let assetId: UUID
            let category: AssetCategory
        }
        var latest: [DedupKey: CategorySnapshotEntry] = [:]
        for entry in entries {
            let key = DedupKey(
                day: cal.startOfDay(for: entry.timestamp),
                accountId: entry.accountId, assetId: entry.assetId,
                category: entry.category)
            if let existing = latest[key], existing.timestamp >= entry.timestamp {
                continue
            }
            latest[key] = entry
        }

        // Step 2: Sum deduped entries by (day, category).
        var grouped: [Date: [AssetCategory: Decimal]] = [:]
        for entry in latest.values {
            let day = cal.startOfDay(for: entry.timestamp)
            grouped[day, default: [:]][entry.category, default: 0] += entry.usdValue
        }

        return grouped.flatMap { date, categories in
            categories.map {
                CategoryChartPoint(
                    date: date, category: $0.key.rawValue.capitalized, value: $0.value)
            }
        }
        .sorted { $0.date < $1.date }
    }

    /// Compute category start/end/change from snapshot entries.
    static func computeCategoryChanges(
        entries: [CategorySnapshotEntry]) -> [CategoryChange] {
        guard !entries.isEmpty else { return [] }
        let cal = Calendar.current
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let firstDay = cal.startOfDay(for: sorted.first!.timestamp)
        let lastDay = cal.startOfDay(for: sorted.last!.timestamp)

        var startValues: [AssetCategory: Decimal] = [:]
        var endValues: [AssetCategory: Decimal] = [:]

        for entry in sorted {
            let day = cal.startOfDay(for: entry.timestamp)
            if day == firstDay { startValues[entry.category, default: 0] += entry.usdValue }
            if day == lastDay { endValues[entry.category, default: 0] += entry.usdValue }
        }

        return AssetCategory.allCases.compactMap { cat in
            let start = startValues[cat, default: 0]
            let end = endValues[cat, default: 0]
            guard start > 0 || end > 0 else { return nil }
            let change = start > 0 ? (end - start) / start : 0
            return CategoryChange(
                name: cat.rawValue.capitalized,
                startValue: start,
                endValue: end,
                percentChange: change)
        }
    }
}
