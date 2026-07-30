import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ValueChangeChartMode: View {
    let accountId: UUID?
    let startDate: Date
    let store: StoreOf<AppFeature>

    @Environment(AppState.self) private var appState

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnaps: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnaps: [AccountSnapshot]
    @Query private var currencyRates: [CurrencyConversionRatePoint]

    init(accountId: UUID?, startDate: Date, store: StoreOf<AppFeature>) {
        self.accountId = accountId
        self.startDate = startDate
        self.store = store
        let historicalStartDate = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        _currencyRates = Query(
            filter: #Predicate<CurrencyConversionRatePoint> { $0.day >= historicalStartDate },
            sort: \.day)
    }

    private var bars: [ValueChangeBar] {
        let observations: [ValueChangeObservation]
        if let accountId {
            let filtered = accountSnaps.filter { $0.accountId == accountId && $0.timestamp >= startDate }
            observations = filtered.map {
                ValueChangeObservation(
                    date: $0.timestamp,
                    value: $0.totalValue,
                    isReliable: $0.isFresh)
            }
        } else {
            let filtered = portfolioSnaps.filter { $0.timestamp >= startDate }
            observations = filtered.map {
                ValueChangeObservation(
                    date: $0.timestamp,
                    value: $0.totalValue,
                    isReliable: $0.isPartial == false)
            }
        }
        let daily = PerformanceFeature.lastValueChangeObservationPerDay(observations)
        return PerformanceFeature.computeValueChangeBars(
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
                    description: Text("Need at least 2 reliable days for Value Change"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 320)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: .day),
                        y: .value("Value Change", bar.change))
                        .foregroundStyle(
                            bar.change >= 0
                                ? PortuTheme.dashboardSuccess
                                : PortuTheme.dashboardWarning)

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

            Text("Value Change includes deposits, withdrawals, and transfers; it is not cost-basis P&L.")
                .font(.caption2)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        }
    }
}
