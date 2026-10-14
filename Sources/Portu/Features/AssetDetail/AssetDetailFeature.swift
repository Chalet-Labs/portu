import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

enum ChartMode: String, CaseIterable, Equatable, Hashable {
    case price = "Price"
    case dollarValue = "Value"
    case amount = "Amount"
}

/// Lightweight input for snapshot aggregation — decouples from SwiftData @Model.
struct SnapshotEntry: Equatable {
    let accountId: UUID
    let assetId: UUID
    let timestamp: Date
    let grossUSD: Decimal
    let borrowUSD: Decimal
    let grossAmount: Decimal
    let borrowAmount: Decimal
}

/// Aggregated chart data point (one per day).
nonisolated struct ChartDataPoint: Identifiable, Equatable {
    let date: Date
    var id: Date {
        date
    }

    let grossUSD: Decimal
    let borrowUSD: Decimal
    let grossAmount: Decimal
    let borrowAmount: Decimal
}

nonisolated struct HistoricalAssetPricePoint: Identifiable, Equatable {
    let day: Date
    var id: Date {
        day
    }

    let price: Decimal
}

// MARK: - AssetDetailFeature

@Reducer
struct AssetDetailFeature {
    @ObservableState
    struct State: Equatable {
        var chartMode: ChartMode = .price
        var selectedRange: ChartTimeRange = .oneMonth
    }

    enum Action: Equatable {
        case chartModeChanged(ChartMode)
        case timeRangeChanged(ChartTimeRange)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .chartModeChanged(mode):
                state.chartMode = mode
                return .none

            case let .timeRangeChanged(range):
                state.selectedRange = range
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Aggregate snapshot entries by day, taking the latest per (day, account, asset) then summing across accounts.
    static func aggregateSnapshots(
        entries: [SnapshotEntry]) -> [ChartDataPoint] {
        let cal = Calendar.current

        // Step 1: For each (day, accountId, assetId), keep only the entry with the latest timestamp.
        struct DedupKey: Hashable {
            let day: Date
            let accountId: UUID
            let assetId: UUID
        }
        var latest: [DedupKey: SnapshotEntry] = [:]
        for entry in entries {
            let key = DedupKey(
                day: cal.startOfDay(for: entry.timestamp),
                accountId: entry.accountId, assetId: entry.assetId)
            if let existing = latest[key], entry.timestamp <= existing.timestamp {
                continue
            }
            latest[key] = entry
        }

        // Step 2: Sum deduped entries across accounts/assets per day.
        var grouped: [Date: (Decimal, Decimal, Decimal, Decimal)] = [:]
        for entry in latest.values {
            let day = cal.startOfDay(for: entry.timestamp)
            var agg = grouped[day] ?? (0, 0, 0, 0)
            agg.0 += entry.grossUSD
            agg.1 += entry.borrowUSD
            agg.2 += entry.grossAmount
            agg.3 += entry.borrowAmount
            grouped[day] = agg
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { date, agg in
                ChartDataPoint(
                    date: date,
                    grossUSD: agg.0,
                    borrowUSD: agg.1,
                    grossAmount: agg.2,
                    borrowAmount: agg.3)
            }
    }

    static func effectiveHistoricalCoinGeckoID(
        assetCoinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity? = nil,
        override: TokenPricingOverrideSnapshot?) -> String? {
        // Read path must use the same key the backfill writer used; priceID mirrors that.
        let coinGeckoId = override?.coinGeckoIdOverride ?? assetCoinGeckoId
        return TokenIdentityMappingFeature.priceID(
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity)
    }

    @MainActor
    static func historicalPriceRows(
        _ rows: [HistoricalPricePoint],
        startDate: Date,
        isHistoricalBackfillEnabled: Bool) -> [HistoricalPricePoint] {
        guard isHistoricalBackfillEnabled else { return [] }
        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        return rows.filter { $0.day >= startDay }
    }

    @MainActor
    static func historicalPricePoints(
        _ rows: [HistoricalPricePoint],
        startDate: Date,
        displayCurrency: FiatCurrency,
        conversionContext: CurrencyConversionContext,
        isHistoricalBackfillEnabled: Bool) -> [HistoricalAssetPricePoint] {
        guard isHistoricalBackfillEnabled else { return [] }
        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        var selectedByDay: [Date: (priority: Int, point: HistoricalAssetPricePoint)] = [:]

        let orderedRows = rows.sorted { lhs, rhs in
            if lhs.fetchedAt == rhs.fetchedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.fetchedAt > rhs.fetchedAt
        }
        for row in orderedRows where row.day >= startDay {
            let normalizedDay = HistoricalPriceCalendar.utcStartOfDay(for: row.day)
            let candidate: (priority: Int, point: HistoricalAssetPricePoint)? = if row.fiatCurrency == displayCurrency {
                (0, HistoricalAssetPricePoint(day: normalizedDay, price: row.price))
            } else if row.fiatCurrency == .usd {
                (
                    1,
                    HistoricalAssetPricePoint(
                        day: normalizedDay,
                        price: conversionContext.convertUSDValue(row.price, on: normalizedDay)))
            } else {
                nil
            }

            guard let candidate else { continue }
            if let existing = selectedByDay[normalizedDay], existing.priority <= candidate.priority {
                continue
            }
            selectedByDay[normalizedDay] = candidate
        }

        return selectedByDay
            .sorted { $0.key < $1.key }
            .map(\.value.point)
    }

    static func convertedValueChartPoints(
        _ points: [ChartDataPoint],
        conversionContext: CurrencyConversionContext) -> [ChartDataPoint] {
        points.map { point in
            ChartDataPoint(
                date: point.date,
                grossUSD: conversionContext.convertUSDValue(point.grossUSD, on: point.date),
                borrowUSD: conversionContext.convertUSDValue(point.borrowUSD, on: point.date),
                grossAmount: point.grossAmount,
                borrowAmount: point.borrowAmount)
        }
    }

    static func historicalPriceEmptyDescription(
        coinGeckoId: String?,
        isHistoricalBackfillEnabled: Bool) -> String {
        guard isHistoricalBackfillEnabled else {
            return "Enable historical price backfill in Settings"
        }
        guard TokenIdentityMappingFeature.normalizedProviderID(coinGeckoId) != nil else {
            return "Set a CoinGecko ID override in Settings"
        }
        return "Run historical price cache from Settings"
    }
}
