// Sources/Portu/Features/Overview/PortfolioValueChart.swift
import Charts
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PortfolioValueChart: View {
    @Query(sort: \PortfolioSnapshot.timestamp)
    private var snapshots: [PortfolioSnapshot]

    @State private var selectedRange: ChartTimeRange = .oneMonth

    private var filteredSnapshots: [PortfolioSnapshot] {
        let start = selectedRange.startDate
        return snapshots.filter { $0.timestamp >= start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Range", selection: $selectedRange) {
                ForEach([ChartTimeRange.oneWeek, .oneMonth, .threeMonths, .oneYear, .ytd], id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .dashboardControl()

            if filteredSnapshots.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see portfolio history"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 190)
            } else {
                Chart(filteredSnapshots, id: \.id) { snapshot in
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
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .chartXAxis {
                    AxisMarks()
                }
                .frame(height: 190)
            }
        }
    }
}
