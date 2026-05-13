// Sources/Portu/Features/Overview/PortfolioValueChart.swift
import Charts
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PortfolioValueChart: View {
    @Query(sort: \PortfolioSnapshot.timestamp)
    private var snapshots: [PortfolioSnapshot]
    @Query(sort: \AssetSnapshot.timestamp)
    private var assetSnapshots: [AssetSnapshot]
    @Query private var assets: [Asset]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query(sort: \HistoricalPricePoint.day)
    private var historicalPrices: [HistoricalPricePoint]

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    private var filteredSnapshots: [PortfolioSnapshot] {
        let start = ChartTimeRange.oneMonth.startDate
        return snapshots.filter { $0.timestamp >= start }
    }

    private var estimatedPoints: [HistoricalPortfolioValuePoint] {
        guard
            historicalBackfillEnabled,
            let firstRealSnapshotDate = assetSnapshots.first?.timestamp
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
            startDate: ChartTimeRange.oneMonth.startDate,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filteredSnapshots.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see portfolio history"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 172)
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

                    ForEach(filteredSnapshots, id: \.id) { snapshot in
                        AreaMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.totalValue))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom))

                        LineMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.totalValue))
                            .foregroundStyle(PortuTheme.dashboardGold)

                        if snapshot.isPartial {
                            PointMark(
                                x: .value("Date", snapshot.timestamp),
                                y: .value("Value", snapshot.totalValue))
                                .symbolSize(20)
                                .foregroundStyle(PortuTheme.dashboardWarning.opacity(0.8))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .chartXAxis {
                    AxisMarks()
                }
                .frame(height: 172)

                if estimatedPoints.isEmpty == false {
                    Text("Dashed segment is estimated from earliest Portu holdings and CoinGecko historical prices.")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .padding(.top, 6)
                }
            }
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
