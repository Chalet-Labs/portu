import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

/// The month of portfolio value from the read model (#124): the chart projector builds it off the
/// main thread and the reducer converts it on a rate, currency or day change, never on a price
/// tick, so a tick doesn't redraw it.
struct PortfolioValueChart: View {
    let store: StoreOf<PortfolioFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let chart = store.valueChart {
                if chart.snapshots.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Sync your accounts to see portfolio history"))
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .frame(height: 172)
                } else {
                    content(chart)
                }
            } else {
                // No chart yet: the first build is loading, or failed and waits for the next
                // trigger. Its error is logged, not shown: the holdings' tooltip is about the headline.
                Text(OverviewPriceDisplay.unvaluedPlaceholder)
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 172, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func content(_ chart: PortfolioValueChartData) -> some View {
        Chart {
            ForEach(chart.estimated) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }

            ForEach(chart.snapshots) { snapshot in
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
                        Text(OverviewPriceDisplay.axisCurrency(amount, currencyCode: chart.currencyCode))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks()
        }
        .frame(height: 172)

        if !chart.estimated.isEmpty {
            Text("Dashed segment is estimated from earliest Portu holdings and cached historical prices.")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .padding(.top, 6)
        }
    }
}
