import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PnLChartMode: View {
    let accountId: UUID?
    let startDate: Date
    let store: StoreOf<AppFeature>

    @Environment(AppState.self) private var appState

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnaps: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnaps: [AccountSnapshot]
    @Query(sort: \CurrencyConversionRatePoint.day) private var currencyRates: [CurrencyConversionRatePoint]

    private var bars: [PnLBar] {
        let rawValues: [(Date, Decimal)]
        if let accountId {
            let filtered = accountSnaps.filter { $0.accountId == accountId && $0.timestamp >= startDate }
            rawValues = filtered.map { ($0.timestamp, $0.totalValue) }
        } else {
            let filtered = portfolioSnaps.filter { $0.timestamp >= startDate }
            rawValues = filtered.map { ($0.timestamp, $0.totalValue) }
        }
        let daily = PerformanceFeature.lastPerDay(rawValues)
        return PerformanceFeature.computePnLBars(
            from: daily,
            conversionContext: currencyConversionContext)
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

    var body: some View {
        VStack(spacing: 8) {
            if bars.isEmpty {
                ContentUnavailableView(
                    "Insufficient Data", systemImage: "chart.bar",
                    description: Text("Need at least 2 days of data for PnL"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 320)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: .day),
                        y: .value("PnL", bar.pnl))
                        .foregroundStyle(bar.pnl >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)

                    if store.performance.showCumulative {
                        LineMark(
                            x: .value("Date", bar.date, unit: .day),
                            y: .value("Cumulative", bar.cumulative))
                            .foregroundStyle(PortuTheme.dashboardGold)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: currencyCode).precision(.fractionLength(0)))
                }
                .frame(height: 320)
            }

            Toggle("Show Cumulative", isOn: Binding(
                get: { store.performance.showCumulative },
                set: { _ in store.send(.performance(.showCumulativeToggled)) }))
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .dashboardControl()
        }
    }
}
