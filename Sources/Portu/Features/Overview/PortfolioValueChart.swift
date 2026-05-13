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

        let chartStartDate = ChartTimeRange.oneMonth.startDate
        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: historicalEstimateSnapshotEntries,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: nil)
        guard !holdings.isEmpty else { return [] }

        return HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: historicalPrices.compactMap {
                guard $0.day >= chartStartDate, $0.day < firstRealSnapshotDate else { return nil }
                return HistoricalPriceEntry(
                    coinGeckoId: $0.coinGeckoId,
                    day: $0.day,
                    usdPrice: $0.usdPrice)
            },
            startDate: chartStartDate,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: nil)
    }

    private var historicalEstimateSnapshotEntries: [HistoricalEstimateSnapshotEntry] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(
            tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return assetSnapshots.map { snapshot in
            HistoricalEstimateSnapshotEntry(
                accountId: snapshot.accountId,
                assetId: snapshot.assetId,
                timestamp: snapshot.timestamp,
                coinGeckoId: assetsById[snapshot.assetId]?.coinGeckoId,
                coinGeckoIdOverride: overridesByAssetId[snapshot.assetId]?.coinGeckoIdOverride,
                amount: snapshot.amount,
                borrowAmount: snapshot.borrowAmount)
        }
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
}
