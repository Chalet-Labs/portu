import Charts
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PortfolioValueChart: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PortfolioSnapshot.timestamp)
    private var snapshots: [PortfolioSnapshot]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query
    private var historicalPrices: [HistoricalPricePoint]
    @Query
    private var currencyRates: [CurrencyConversionRatePoint]

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    /// Pre-computed estimated segment, refreshed via `.task(id: estimateInputs)`.
    /// Body only renders this array — no models touched during evaluation.
    @State private var estimatedPoints: [HistoricalPortfolioValuePoint] = []

    init() {
        let historicalStartDate = HistoricalPriceCalendar.utcStartOfDay(for: ChartTimeRange.oneMonth.startDate)
        _historicalPrices = Query(
            filter: #Predicate<HistoricalPricePoint> { $0.day >= historicalStartDate },
            sort: \.day)
        _currencyRates = Query(
            filter: #Predicate<CurrencyConversionRatePoint> { $0.day >= historicalStartDate },
            sort: \.day)
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        let start = ChartTimeRange.oneMonth.startDate
        return snapshots.filter { $0.timestamp >= start }
    }

    private var convertedSnapshots: [(id: UUID, timestamp: Date, value: Decimal, isPartial: Bool)] {
        let context = currencyConversionContext
        return filteredSnapshots.map { snapshot in
            (
                id: snapshot.id,
                timestamp: snapshot.timestamp,
                value: context.convertUSDValue(snapshot.totalValue, on: snapshot.timestamp),
                isPartial: snapshot.isPartial)
        }
    }

    private var currencyConversionContext: CurrencyConversionContext {
        CurrencyConversionContext(
            displayCurrency: appState.selectedCurrency,
            currentUSDToDisplayRate: appState.currentUSDToDisplayRate,
            historicalRatePoints: currencyRates)
    }

    private var currencyCode: String {
        appState.selectedCurrency.displayCode
    }

    /// Stamp driving estimate recomputation via `.task(id:)`.
    ///
    /// `portfolioSnapshotCount` / `lastPortfolioSnapshotTimestamp`: count-keyed because
    /// `PortfolioSnapshot` rows are insert/delete-only — SyncEngine creates them once and
    /// retention prunes; no in-place mutation sites exist. Count is also the proxy for
    /// same-flow `AssetSnapshot` writes.
    ///
    /// `priceEntries` / `rateContent` / `overrideSnapshots`: content-keyed because
    /// `CurrencyConversionClient.update(rate:fetchedAt:)` mutates rate rows in place and
    /// `TokenPricingOverrideWriter` upserts override fields in place — count alone would
    /// miss those mutations.
    private struct EstimateInputs: Equatable {
        struct CurrencyRateContent: Equatable {
            var baseCurrency: FiatCurrency
            var quoteCurrency: FiatCurrency
            var day: Date
            var rate: Decimal
        }

        var portfolioSnapshotCount: Int
        var lastPortfolioSnapshotTimestamp: Date?
        var priceEntries: [HistoricalPriceEntry]
        var rateContent: [CurrencyRateContent]
        var overrideSnapshots: [TokenPricingOverrideSnapshot]
        var currencyCode: String
        var currentUSDToDisplayRate: Decimal
        var backfillEnabled: Bool
    }

    private var estimateInputs: EstimateInputs {
        // With backfill disabled the estimate is definitionally empty (see
        // PortfolioValueChartFeature.estimatedPoints), so skip the per-body
        // mapping below entirely — matching master's disabled path, which
        // guarded before any price work. `backfillEnabled` stays in the stamp
        // so toggling the setting still triggers recomputation.
        guard historicalBackfillEnabled else {
            return EstimateInputs(
                portfolioSnapshotCount: snapshots.count,
                lastPortfolioSnapshotTimestamp: snapshots.last?.timestamp,
                priceEntries: [],
                rateContent: [],
                overrideSnapshots: [],
                currencyCode: appState.selectedCurrency.displayCode,
                currentUSDToDisplayRate: appState.currentUSDToDisplayRate,
                backfillEnabled: false)
        }

        let chartStartDate = ChartTimeRange.oneMonth.startDate
        let chartStartDay = HistoricalPriceCalendar.utcStartOfDay(for: chartStartDate)
        // Per-body mapping is bounded by the one-month predicated price/rate window (the
        // same rows the estimator consumes), a few ms at real-store scale — versus the
        // ~1.9 s body-time chain this replaces.
        return EstimateInputs(
            portfolioSnapshotCount: snapshots.count,
            lastPortfolioSnapshotTimestamp: snapshots.last?.timestamp,
            priceEntries: historicalPrices.compactMap { point -> HistoricalPriceEntry? in
                guard point.fiatCurrency == .usd, point.day >= chartStartDay else { return nil }
                return HistoricalPriceEntry(
                    coinGeckoId: point.coinGeckoId,
                    day: point.day,
                    usdPrice: point.usdPrice)
            },
            rateContent: currencyRates.map {
                EstimateInputs.CurrencyRateContent(
                    baseCurrency: $0.baseCurrency,
                    quoteCurrency: $0.quoteCurrency,
                    day: $0.day,
                    rate: $0.rate)
            },
            overrideSnapshots: tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init),
            currencyCode: appState.selectedCurrency.displayCode,
            currentUSDToDisplayRate: appState.currentUSDToDisplayRate,
            backfillEnabled: true)
    }

    @MainActor
    private func reloadEstimatedPoints(_ inputs: EstimateInputs) async {
        // `.task(id:)` cancels a superseded reload, but cancellation is cooperative:
        // the fetch still runs to completion. Drop superseded results instead of
        // writing them, so a stale reload can never overwrite the state a newer
        // one already produced — checked before any state write, including the
        // clears below, because the synchronous prefix also runs after cancel.
        guard !Task.isCancelled else { return }
        guard inputs.backfillEnabled else {
            estimatedPoints = []
            return
        }

        let chartStartDate = ChartTimeRange.oneMonth.startDate
        let fetcher = PortfolioValueChartEstimateFetcher(modelContainer: modelContext.container)
        let source = await fetcher.estimateSource(
            overrides: inputs.overrideSnapshots,
            chartStartDate: chartStartDate)
        guard !Task.isCancelled else { return }
        guard let source else {
            estimatedPoints = []
            return
        }
        let context = currencyConversionContext
        estimatedPoints = PortfolioValueChartFeature.estimatedPoints(
            source: source,
            prices: inputs.priceEntries,
            chartStartDate: chartStartDate,
            isBackfillEnabled: inputs.backfillEnabled)
            .map { context.convertUSDPoint($0) }
    }

    var body: some View {
        // Single evaluation of the stamp: the `.task(id:)` argument and the
        // reload argument share one mapped copy instead of mapping the
        // price/rate windows twice per refresh.
        let inputs = estimateInputs
        return VStack(alignment: .leading, spacing: 0) {
            let snapshots = convertedSnapshots
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see portfolio history"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 172)
            } else {
                Chart {
                    ForEach(estimatedPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value))
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }

                    ForEach(snapshots, id: \.id) { snapshot in
                        AreaMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.value))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom))

                        LineMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.value))
                            .foregroundStyle(PortuTheme.dashboardGold)

                        if snapshot.isPartial {
                            PointMark(
                                x: .value("Date", snapshot.timestamp),
                                y: .value("Value", snapshot.value))
                                .symbolSize(20)
                                .foregroundStyle(PortuTheme.dashboardWarning.opacity(0.8))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(OverviewPriceDisplay.axisCurrency(amount, currencyCode: currencyCode))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks()
                }
                .frame(height: 172)

                if estimatedPoints.isEmpty == false {
                    Text("Dashed segment is estimated from earliest Portu holdings and cached historical prices.")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .padding(.top, 6)
                }
            }
        }
        .task(id: inputs) { await reloadEstimatedPoints(inputs) }
    }
}
