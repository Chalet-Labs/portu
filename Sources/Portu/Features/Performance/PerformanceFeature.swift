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

/// Period price change keyed by historical price ID. The ID is `<coinGeckoId>` for
/// CoinGecko-priced assets and `zapper:<chain>:<contract>` for onchain assets whose
/// prices come from Zapper, matching the cache's `HistoricalPricePoint.coinGeckoId`
/// convention.
struct AssetPricePeriodChange: Identifiable, Equatable {
    var id: String {
        historicalPriceID
    }

    let historicalPriceID: String
    let name: String
    let startPrice: Decimal
    let endPrice: Decimal
    let percentChange: Decimal

    init(
        historicalPriceID: String,
        name: String? = nil,
        startPrice: Decimal,
        endPrice: Decimal,
        percentChange: Decimal) {
        self.historicalPriceID = historicalPriceID
        self.name = name ?? historicalPriceID
        self.startPrice = startPrice
        self.endPrice = endPrice
        self.percentChange = percentChange
    }
}

/// Per-(account, asset) snapshot used to derive earliest holdings and to feed
/// the pre-snapshot value estimator that backfills chart data before the first
/// real local snapshot.
struct HistoricalEstimateSnapshotEntry: Equatable {
    let accountId: UUID
    let assetId: UUID
    let timestamp: Date
    let coinGeckoId: String?
    let coinGeckoIdOverride: String?
    var onchainIdentity: OnchainTokenIdentity?
    let amount: Decimal
    let borrowAmount: Decimal
    let netUSDValue: Decimal?

    init(
        accountId: UUID,
        assetId: UUID,
        timestamp: Date,
        coinGeckoId: String?,
        coinGeckoIdOverride: String?,
        onchainIdentity: OnchainTokenIdentity? = nil,
        amount: Decimal,
        borrowAmount: Decimal,
        netUSDValue: Decimal? = nil) {
        self.accountId = accountId
        self.assetId = assetId
        self.timestamp = timestamp
        self.coinGeckoId = coinGeckoId
        self.coinGeckoIdOverride = coinGeckoIdOverride
        self.onchainIdentity = onchainIdentity
        self.amount = amount
        self.borrowAmount = borrowAmount
        self.netUSDValue = netUSDValue
    }
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
    /// Uses UTC day boundaries to align with the historical price cache.
    private static func deduplicateByDayAndAsset(
        _ entries: [CategorySnapshotEntry]) -> [CategorySnapshotEntry] {
        struct DedupKey: Hashable {
            let day: Date
            let accountId: UUID
            let assetId: UUID
        }
        var latest: [DedupKey: CategorySnapshotEntry] = [:]
        for entry in entries {
            let key = DedupKey(
                day: utcStartOfDay(for: entry.timestamp),
                accountId: entry.accountId, assetId: entry.assetId)
            if let existing = latest[key], existing.timestamp >= entry.timestamp {
                continue
            }
            latest[key] = entry
        }
        return Array(latest.values)
    }

    /// Keep only the last value per UTC day, sorted ascending. UTC bucketing keeps
    /// real-snapshot points aligned with historical-price-derived estimated points
    /// when they share a chart.
    static func lastPerDay(_ values: [(Date, Decimal)]) -> [(Date, Decimal)] {
        var byDay: [Date: (Date, Decimal)] = [:]
        for (date, value) in values {
            let day = utcStartOfDay(for: date)
            if let existing = byDay[day] {
                if date > existing.0 { byDay[day] = (date, value) }
            } else {
                byDay[day] = (date, value)
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
    /// Uses UTC day boundaries to align with the historical price cache.
    static func aggregateCategorySnapshots(
        entries: [CategorySnapshotEntry]) -> [CategoryChartPoint] {
        let deduped = deduplicateByDayAndAsset(entries)

        var grouped: [Date: [String: (name: String, value: Decimal)]] = [:]
        for entry in deduped {
            let day = utcStartOfDay(for: entry.timestamp)
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
        entries: [CategorySnapshotEntry],
        visibleAssetIDs: Set<UUID>? = nil) -> [CategoryChange] {
        let scopedEntries = visibleAssetIDs.map { ids in
            entries.filter { ids.contains($0.assetId) }
        } ?? entries
        guard !scopedEntries.isEmpty else { return [] }
        let sorted = scopedEntries.sorted { $0.timestamp < $1.timestamp }
        let firstDay = utcStartOfDay(for: sorted.first!.timestamp)
        let lastDay = utcStartOfDay(for: sorted.last!.timestamp)
        let deduped = deduplicateByDayAndAsset(sorted)

        var namesByID: [String: String] = [:]
        var startValues: [String: Decimal] = [:]
        var endValues: [String: Decimal] = [:]

        for entry in deduped {
            let day = utcStartOfDay(for: entry.timestamp)
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
        let normalizedRows = rows.compactMap { row -> HistoricalPriceEntry? in
            guard let historicalPriceID = normalizedHistoricalPriceID(row.coinGeckoId) else { return nil }
            return HistoricalPriceEntry(coinGeckoId: historicalPriceID, day: row.day, usdPrice: row.usdPrice)
        }
        let grouped = Dictionary(grouping: normalizedRows) { $0.coinGeckoId }
        return grouped.keys.sorted().compactMap { historicalPriceID in
            // Dedupe per day before picking endpoints — multiple rows per (coinGeckoId, day) can
            // exist transiently, and sorting by (day, usdPrice) would otherwise pick the lowest
            // price on the earliest day and highest on the latest, inflating percentChange.
            let perDay = Dictionary(grouping: grouped[historicalPriceID, default: []], by: \.day)
                .compactMap { _, entries -> HistoricalPriceEntry? in entries.last }
            let sorted = perDay.sorted { $0.day < $1.day }
            guard
                let first = sorted.first,
                let last = sorted.last,
                first.usdPrice > 0
            else { return nil }
            return AssetPricePeriodChange(
                historicalPriceID: historicalPriceID,
                startPrice: first.usdPrice,
                endPrice: last.usdPrice,
                percentChange: (last.usdPrice - first.usdPrice) / first.usdPrice)
        }
    }

    static func applyAssetDisplayNames(
        changes: [AssetPricePeriodChange],
        namesByHistoricalPriceID: [String: String]) -> [AssetPricePeriodChange] {
        let normalizedNames = Dictionary(
            namesByHistoricalPriceID.compactMap { id, name -> (String, String)? in
                guard let normalizedID = normalizedHistoricalPriceID(id) else { return nil }
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return nil }
                return (normalizedID, trimmedName)
            },
            uniquingKeysWith: { lhs, _ in lhs })

        return changes.map { change in
            AssetPricePeriodChange(
                historicalPriceID: change.historicalPriceID,
                name: normalizedNames[change.historicalPriceID] ?? change.name,
                startPrice: change.startPrice,
                endPrice: change.endPrice,
                percentChange: change.percentChange)
        }
    }

    static func earliestEstimateHoldings(
        snapshots: [HistoricalEstimateSnapshotEntry],
        firstRealSnapshotDate: Date,
        accountId: UUID?) -> [HistoricalEstimateHolding] {
        let firstDay = utcStartOfDay(for: firstRealSnapshotDate)
        return earliestEstimateSnapshots(on: firstDay, snapshots: snapshots, accountId: accountId)
            .compactMap { snapshot in
                let netAmount = snapshot.amount - snapshot.borrowAmount
                guard netAmount != 0, let coinGeckoId = resolvedCoinGeckoID(snapshot) else { return nil }
                return HistoricalEstimateHolding(
                    accountId: snapshot.accountId,
                    assetId: snapshot.assetId,
                    coinGeckoId: coinGeckoId,
                    amount: netAmount,
                    fallbackUSDValue: snapshot.netUSDValue)
            }
    }

    static func historicalPriceEntriesForHeldAssets(
        rows: [HistoricalPriceEntry],
        holdings: [HistoricalEstimateSnapshotEntry],
        startDate: Date,
        accountId: UUID?,
        isHistoricalBackfillEnabled: Bool) -> [HistoricalPriceEntry] {
        guard isHistoricalBackfillEnabled else { return [] }
        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        let heldIDs = heldHistoricalCoinGeckoIDs(
            snapshots: holdings,
            startDate: startDay,
            accountId: accountId)
        guard heldIDs.isEmpty == false else { return [] }

        return rows.compactMap { row in
            guard let coinGeckoId = normalizedHistoricalPriceID(row.coinGeckoId) else { return nil }
            guard row.day >= startDay, heldIDs.contains(coinGeckoId) else { return nil }
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

    private static func earliestEstimateSnapshots(
        on day: Date,
        snapshots: [HistoricalEstimateSnapshotEntry],
        accountId: UUID?) -> [HistoricalEstimateSnapshotEntry] {
        struct SnapshotKey: Hashable {
            let accountId: UUID
            let assetId: UUID
        }

        var earliestByKey: [SnapshotKey: HistoricalEstimateSnapshotEntry] = [:]
        for snapshot in snapshots where utcStartOfDay(for: snapshot.timestamp) == day {
            guard accountId == nil || snapshot.accountId == accountId else { continue }
            let key = SnapshotKey(accountId: snapshot.accountId, assetId: snapshot.assetId)
            if let existing = earliestByKey[key], existing.timestamp <= snapshot.timestamp {
                continue
            }
            earliestByKey[key] = snapshot
        }

        return earliestByKey.values.sorted {
            if $0.accountId != $1.accountId { return $0.accountId.uuidString < $1.accountId.uuidString }
            return $0.assetId.uuidString < $1.assetId.uuidString
        }
    }

    private static func resolvedCoinGeckoID(_ snapshot: HistoricalEstimateSnapshotEntry) -> String? {
        // Read path must use the same key the backfill writer used; priceID mirrors that.
        let coinGeckoId = snapshot.coinGeckoIdOverride ?? snapshot.coinGeckoId
        return TokenIdentityMappingFeature.priceID(
            coinGeckoId: coinGeckoId,
            onchainIdentity: snapshot.onchainIdentity)
    }

    private static func normalizedHistoricalPriceID(_ id: String?) -> String? {
        TokenIdentityMappingFeature.normalizedHistoricalPriceID(id)
    }

    private static func utcStartOfDay(for date: Date) -> Date {
        HistoricalPriceCalendar.utcStartOfDay(for: date)
    }
}
