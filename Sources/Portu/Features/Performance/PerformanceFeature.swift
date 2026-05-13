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
    let id: String
    let name: String
    let startValue: Decimal
    let endValue: Decimal
    let percentChange: Decimal
}

/// Price change for one cached CoinGecko asset over a period.
struct AssetPricePeriodChange: Identifiable, Equatable {
    var id: String {
        coinGeckoId
    }

    let coinGeckoId: String
    let startPrice: Decimal
    let endPrice: Decimal
    let percentChange: Decimal
}

/// Snapshot input used for estimated history and held-price filtering.
struct HistoricalEstimateSnapshotEntry: Equatable {
    let accountId: UUID
    let assetId: UUID
    let timestamp: Date
    let coinGeckoId: String?
    let coinGeckoIdOverride: String?
    let amount: Decimal
    let borrowAmount: Decimal
}

/// Lightweight input for category change and chart aggregation.
struct CategorySnapshotEntry: Equatable {
    let accountId: UUID
    let assetId: UUID
    let timestamp: Date
    let category: AssetCategory
    let categoryID: String
    let categoryName: String
    let usdValue: Decimal

    init(
        accountId: UUID,
        assetId: UUID,
        timestamp: Date,
        category: AssetCategory,
        categoryID: String? = nil,
        categoryName: String? = nil,
        usdValue: Decimal) {
        self.accountId = accountId
        self.assetId = assetId
        self.timestamp = timestamp
        self.category = category
        self.categoryID = categoryID ?? category.rawValue
        self.categoryName = categoryName ?? category.rawValue.capitalized
        self.usdValue = usdValue
    }

    @MainActor
    init(
        snapshot: AssetSnapshot,
        categoryResolver: PortfolioCategoryResolver = .defaults) {
        let resolved = categoryResolver.resolve(
            symbol: snapshot.symbol,
            legacyCategory: snapshot.category)
        self.init(
            accountId: snapshot.accountId,
            assetId: snapshot.assetId,
            timestamp: snapshot.timestamp,
            category: snapshot.category,
            categoryID: resolved.id.uuidString,
            categoryName: resolved.name,
            usdValue: snapshot.usdValue)
    }
}

/// Aggregated category chart data point (one per day per category).
struct CategoryChartPoint: Equatable {
    let date: Date
    let categoryID: String
    let categoryName: String
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
        var disabledPortfolioCategoryIDs: Set<String> = []
        var showCumulative: Bool = false
    }

    enum Action: Equatable {
        case accountSelected(UUID?)
        case timeRangeChanged(ChartTimeRange)
        case chartModeChanged(PerformanceChartMode)
        case portfolioCategoryToggled(String)
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

            case let .portfolioCategoryToggled(id):
                if state.disabledPortfolioCategoryIDs.contains(id) {
                    state.disabledPortfolioCategoryIDs.remove(id)
                } else {
                    state.disabledPortfolioCategoryIDs.insert(id)
                }
                return .none

            case .showCumulativeToggled:
                state.showCumulative.toggle()
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Deduplicate snapshot entries: for each (day, accountId, assetId), keep only the latest timestamp.
    /// Category is excluded from the key so a mid-day category change doesn't cause double-counting.
    private static func deduplicateByDayAndAsset(
        _ entries: [CategorySnapshotEntry]) -> [CategorySnapshotEntry] {
        let cal = Calendar.current
        struct DedupKey: Hashable {
            let day: Date
            let accountId: UUID
            let assetId: UUID
        }
        var latest: [DedupKey: CategorySnapshotEntry] = [:]
        for entry in entries {
            let key = DedupKey(
                day: cal.startOfDay(for: entry.timestamp),
                accountId: entry.accountId, assetId: entry.assetId)
            if let existing = latest[key], existing.timestamp >= entry.timestamp {
                continue
            }
            latest[key] = entry
        }
        return Array(latest.values)
    }

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
    /// Deduplicates by taking the latest snapshot per (day, accountId, assetId),
    /// then sums across unique (accountId, assetId) combinations per (day, category).
    static func aggregateCategorySnapshots(
        entries: [CategorySnapshotEntry]) -> [CategoryChartPoint] {
        let cal = Calendar.current
        let deduped = deduplicateByDayAndAsset(entries)

        var grouped: [Date: [String: (name: String, value: Decimal)]] = [:]
        for entry in deduped {
            let day = cal.startOfDay(for: entry.timestamp)
            var category = grouped[day, default: [:]][entry.categoryID] ?? (entry.categoryName, 0)
            category.value += entry.usdValue
            grouped[day, default: [:]][entry.categoryID] = category
        }

        return grouped.flatMap { date, categories in
            categories.map {
                CategoryChartPoint(
                    date: date,
                    categoryID: $0.key,
                    categoryName: $0.value.name,
                    value: $0.value.value)
            }
        }
        .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            let nameOrder = $0.categoryName.localizedStandardCompare($1.categoryName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.categoryID < $1.categoryID
        }
    }

    /// Compute category start/end/change from snapshot entries.
    static func computeCategoryChanges(
        entries: [CategorySnapshotEntry]) -> [CategoryChange] {
        guard !entries.isEmpty else { return [] }
        let cal = Calendar.current
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let firstDay = cal.startOfDay(for: sorted.first!.timestamp)
        let lastDay = cal.startOfDay(for: sorted.last!.timestamp)
        let deduped = deduplicateByDayAndAsset(sorted)

        var namesByID: [String: String] = [:]
        var startValues: [String: Decimal] = [:]
        var endValues: [String: Decimal] = [:]

        for entry in deduped {
            let day = cal.startOfDay(for: entry.timestamp)
            namesByID[entry.categoryID] = entry.categoryName
            if day == firstDay { startValues[entry.categoryID, default: 0] += entry.usdValue }
            if day == lastDay { endValues[entry.categoryID, default: 0] += entry.usdValue }
        }

        return namesByID.keys.sorted { lhs, rhs in
            (namesByID[lhs] ?? lhs).localizedStandardCompare(namesByID[rhs] ?? rhs) == .orderedAscending
        }.compactMap { id in
            let start = startValues[id, default: 0]
            let end = endValues[id, default: 0]
            guard start > 0 || end > 0 else { return nil }
            let change = start > 0 ? (end - start) / start : 0
            return CategoryChange(
                id: id,
                name: namesByID[id] ?? id,
                startValue: start,
                endValue: end,
                percentChange: change)
        }
    }

    static func computeHistoricalPriceChanges(
        rows: [HistoricalPriceEntry]) -> [AssetPricePeriodChange] {
        let grouped = Dictionary(grouping: rows) { $0.coinGeckoId }
        return grouped.keys.sorted().compactMap { coinGeckoId in
            let sorted = grouped[coinGeckoId, default: []].sorted {
                if $0.day != $1.day { return $0.day < $1.day }
                return $0.usdPrice < $1.usdPrice
            }
            guard
                let first = sorted.first,
                let last = sorted.last,
                first.usdPrice > 0
            else { return nil }
            return AssetPricePeriodChange(
                coinGeckoId: coinGeckoId,
                startPrice: first.usdPrice,
                endPrice: last.usdPrice,
                percentChange: (last.usdPrice - first.usdPrice) / first.usdPrice)
        }
    }

    static func earliestEstimateHoldings(
        snapshots: [HistoricalEstimateSnapshotEntry],
        firstRealSnapshotDate: Date,
        accountId: UUID?) -> [HistoricalEstimateHolding] {
        let firstDay = utcStartOfDay(for: firstRealSnapshotDate)
        return latestEstimateSnapshots(on: firstDay, snapshots: snapshots, accountId: accountId)
            .compactMap { snapshot in
                let netAmount = snapshot.amount - snapshot.borrowAmount
                guard netAmount != 0, let coinGeckoId = resolvedCoinGeckoID(snapshot) else { return nil }
                return HistoricalEstimateHolding(
                    accountId: snapshot.accountId,
                    assetId: snapshot.assetId,
                    coinGeckoId: coinGeckoId,
                    amount: netAmount)
            }
    }

    static func historicalPriceEntriesForHeldAssets(
        rows: [HistoricalPriceEntry],
        holdings: [HistoricalEstimateSnapshotEntry],
        startDate: Date,
        accountId: UUID?,
        isHistoricalBackfillEnabled: Bool) -> [HistoricalPriceEntry] {
        guard isHistoricalBackfillEnabled else { return [] }
        let heldIDs = heldHistoricalCoinGeckoIDs(
            snapshots: holdings,
            startDate: startDate,
            accountId: accountId)
        guard heldIDs.isEmpty == false else { return [] }

        return rows.compactMap { row in
            let coinGeckoId = normalizedCoinGeckoID(row.coinGeckoId)
            guard row.day >= startDate, heldIDs.contains(coinGeckoId) else { return nil }
            return HistoricalPriceEntry(
                coinGeckoId: coinGeckoId,
                day: row.day,
                usdPrice: row.usdPrice)
        }
    }

    private static func heldHistoricalCoinGeckoIDs(
        snapshots: [HistoricalEstimateSnapshotEntry],
        startDate: Date,
        accountId: UUID?) -> Set<String> {
        Set(snapshots.compactMap { snapshot in
            guard snapshot.timestamp >= startDate else { return nil }
            guard accountId == nil || snapshot.accountId == accountId else { return nil }
            guard snapshot.amount - snapshot.borrowAmount != 0 else { return nil }
            return resolvedCoinGeckoID(snapshot)
        })
    }

    private static func latestEstimateSnapshots(
        on day: Date,
        snapshots: [HistoricalEstimateSnapshotEntry],
        accountId: UUID?) -> [HistoricalEstimateSnapshotEntry] {
        struct SnapshotKey: Hashable {
            let accountId: UUID
            let assetId: UUID
        }

        var latestByKey: [SnapshotKey: HistoricalEstimateSnapshotEntry] = [:]
        for snapshot in snapshots where utcStartOfDay(for: snapshot.timestamp) == day {
            guard accountId == nil || snapshot.accountId == accountId else { continue }
            let key = SnapshotKey(accountId: snapshot.accountId, assetId: snapshot.assetId)
            if let existing = latestByKey[key], existing.timestamp >= snapshot.timestamp {
                continue
            }
            latestByKey[key] = snapshot
        }

        return latestByKey.values.sorted {
            if $0.accountId != $1.accountId { return $0.accountId.uuidString < $1.accountId.uuidString }
            return $0.assetId.uuidString < $1.assetId.uuidString
        }
    }

    private static func resolvedCoinGeckoID(_ snapshot: HistoricalEstimateSnapshotEntry) -> String? {
        normalizedOptionalCoinGeckoID(snapshot.coinGeckoIdOverride)
            ?? normalizedOptionalCoinGeckoID(snapshot.coinGeckoId)
    }

    private static func normalizedOptionalCoinGeckoID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = normalizedCoinGeckoID(id)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedCoinGeckoID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}
