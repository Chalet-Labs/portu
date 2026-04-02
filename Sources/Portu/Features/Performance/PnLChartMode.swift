import Charts
import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct PnLChartMode: View {
    let accountId: UUID?
    let startDate: Date
    let store: StoreOf<AppFeature>

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnaps: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnaps: [AccountSnapshot]

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
        return PerformanceFeature.computePnLBars(from: daily)
    }

    var body: some View {
        VStack(spacing: 8) {
            if bars.isEmpty {
                ContentUnavailableView(
                    "Insufficient Data", systemImage: "chart.bar",
                    description: Text("Need at least 2 days of data for PnL")
                )
                .frame(height: 300)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: .day),
                        y: .value("PnL", bar.pnl)
                    )
                    .foregroundStyle(bar.pnl >= 0 ? Color.green : Color.red)

                    if store.performance.showCumulative {
                        LineMark(
                            x: .value("Date", bar.date, unit: .day),
                            y: .value("Cumulative", bar.cumulative)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 300)
                .padding()
            }

            Toggle("Show Cumulative", isOn: Binding(
                get: { store.performance.showCumulative },
                set: { _ in store.send(.performance(.showCumulativeToggled)) }
            ))
            .padding(.horizontal)
        }
    }
}
