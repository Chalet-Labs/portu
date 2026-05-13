import Charts
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ValueChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \PortfolioSnapshot.timestamp)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @Query(sort: \AccountSnapshot.timestamp)
    private var accountSnapshots: [AccountSnapshot]

    @Query(sort: \AssetSnapshot.timestamp)
    private var assetSnapshots: [AssetSnapshot]

    @Query private var assets: [Asset]

    @Query private var tokenPricingOverrides: [TokenPricingOverride]

    @Query(sort: \HistoricalPricePoint.day)
    private var historicalPrices: [HistoricalPricePoint]

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    private var dataPoints: [(Date, Decimal, Bool)] {
        if let accountId {
            accountSnapshots
                .filter { $0.accountId == accountId && $0.timestamp >= startDate }
                .map { ($0.timestamp, $0.totalValue, !$0.isFresh) }
        } else {
            portfolioSnapshots
                .filter { $0.timestamp >= startDate }
                .map { ($0.timestamp, $0.totalValue, $0.isPartial) }
        }
    }

    private var estimatedPoints: [HistoricalPortfolioValuePoint] {
        guard
            historicalBackfillEnabled,
            let firstRealSnapshotDate = dataPoints.map(\.0).min()
        else { return [] }

        let holdings = earliestHoldings(firstRealSnapshotDate: firstRealSnapshotDate)
        guard !holdings.isEmpty else { return [] }

        return HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: historicalPrices.map {
                HistoricalPriceEntry(
                    coinGeckoId: $0.coinGeckoId,
                    day: $0.day,
                    usdPrice: $0.usdPrice)
            },
            startDate: startDate,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: accountId)
    }

    var body: some View {
        if dataPoints.isEmpty {
            ContentUnavailableView(
                "No Performance Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Sync your accounts to track portfolio performance"))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .frame(height: 320)
        } else {
            let estimatedPoints = estimatedPoints
            Chart {
                ForEach(estimatedPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value))
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }

                ForEach(dataPoints, id: \.0) { date, value, isPartial in
                    AreaMark(x: .value("Date", date), y: .value("Value", value))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [PortuTheme.dashboardGold.opacity(0.35), .clear],
                                startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", date), y: .value("Value", value))
                        .foregroundStyle(PortuTheme.dashboardGold)
                        .lineStyle(isPartial ? StrokeStyle(lineWidth: 2, dash: [5, 3]) : StrokeStyle(lineWidth: 2))
                }
            }
            .chartYAxis {
                AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
            }
            .frame(height: 320)
        }
    }

    private func earliestHoldings(firstRealSnapshotDate: Date) -> [HistoricalEstimateHolding] {
        let firstDay = Self.utcStartOfDay(for: firstRealSnapshotDate)
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(
            tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return latestSnapshots(on: firstDay).compactMap { snapshot in
            guard
                let coinGeckoId = resolvedCoinGeckoId(
                    assetId: snapshot.assetId,
                    assetsById: assetsById,
                    overridesByAssetId: overridesByAssetId)
            else { return nil }

            return HistoricalEstimateHolding(
                accountId: snapshot.accountId,
                assetId: snapshot.assetId,
                coinGeckoId: coinGeckoId,
                amount: snapshot.amount - snapshot.borrowAmount)
        }
    }

    private func latestSnapshots(on day: Date) -> [AssetSnapshot] {
        struct SnapshotKey: Hashable {
            let accountId: UUID
            let assetId: UUID
        }
        var latestByKey: [SnapshotKey: AssetSnapshot] = [:]
        for snapshot in assetSnapshots where Self.utcStartOfDay(for: snapshot.timestamp) == day {
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

    private func resolvedCoinGeckoId(
        assetId: UUID,
        assetsById: [UUID: Asset],
        overridesByAssetId: [UUID: TokenPricingOverrideSnapshot]) -> String? {
        Self.normalizedCoinGeckoId(overridesByAssetId[assetId]?.coinGeckoIdOverride)
            ?? Self.normalizedCoinGeckoId(assetsById[assetId]?.coinGeckoId)
    }

    private static func normalizedCoinGeckoId(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}
