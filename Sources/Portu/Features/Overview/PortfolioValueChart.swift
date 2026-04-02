// Sources/Portu/Features/Overview/PortfolioValueChart.swift
import Charts
import PortuCore
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
        VStack(alignment: .leading, spacing: 8) {
            // Time range picker
            Picker("Range", selection: $selectedRange) {
                ForEach([ChartTimeRange.oneWeek, .oneMonth, .threeMonths, .oneYear, .ytd], id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            if filteredSnapshots.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see portfolio history"))
                    .frame(height: 200)
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
                        .foregroundStyle(Color.accentColor)

                    // Partial snapshot indicator
                    if snapshot.isPartial {
                        PointMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.totalValue))
                            .symbolSize(20)
                            .foregroundStyle(.orange.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 250)
            }
        }
    }
}
