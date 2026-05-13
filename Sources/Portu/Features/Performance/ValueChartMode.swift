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

    private var scopedAssetSnapshots: [AssetSnapshot] {
        assetSnapshots.filter { accountId == nil || $0.accountId == accountId }
    }

    private var estimatedPoints: [HistoricalPortfolioValuePoint] {
        guard
            historicalBackfillEnabled,
            let firstRealSnapshotDate = scopedAssetSnapshots.map(\.timestamp).min()
        else { return [] }

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: historicalEstimateSnapshotEntries,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: accountId)
        guard !holdings.isEmpty else { return [] }

        return HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: historicalPrices.compactMap {
                guard $0.day >= startDate, $0.day < firstRealSnapshotDate else { return nil }
                return HistoricalPriceEntry(
                    coinGeckoId: $0.coinGeckoId,
                    day: $0.day,
                    usdPrice: $0.usdPrice)
            },
            startDate: startDate,
            firstRealSnapshotDate: firstRealSnapshotDate,
            accountId: accountId)
    }

    private var historicalEstimateSnapshotEntries: [HistoricalEstimateSnapshotEntry] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(
            tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return scopedAssetSnapshots.map { snapshot in
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
}
