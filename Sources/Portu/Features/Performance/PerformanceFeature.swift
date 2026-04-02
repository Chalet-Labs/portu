import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

enum PerformanceChartMode: String, CaseIterable, Equatable, Hashable {
    case value = "Value"
    case assets = "Assets"
    case pnl = "PnL"
}

enum PerformanceTimeRange: String, CaseIterable, Equatable, Hashable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case ytd = "YTD"
    case custom = "Custom"

    var startDate: Date {
        let cal = Calendar.current
        let now = Date.now
        return switch self {
        case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
        case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
        case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
        case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
        case .ytd: cal.date(from: cal.dateComponents([.year], from: now))!
        case .custom: cal.date(byAdding: .month, value: -1, to: now)!
        }
    }
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

/// Lightweight input for category change computation.
struct CategorySnapshotEntry: Equatable {
    let timestamp: Date
    let category: AssetCategory
    let usdValue: Decimal
}

// MARK: - PerformanceFeature

@Reducer
struct PerformanceFeature {
    @ObservableState
    struct State: Equatable {
        var selectedAccountId: UUID?
        var selectedRange: PerformanceTimeRange = .oneMonth
        var chartMode: PerformanceChartMode = .value
        var disabledCategories: Set<AssetCategory> = []
        var showCumulative: Bool = false
    }

    enum Action: Equatable {
        case accountSelected(UUID?)
        case timeRangeChanged(PerformanceTimeRange)
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
