// Sources/Portu/Features/Overview/PortfolioValueChart.swift
import Charts
import PortuCore
import SwiftData
import SwiftUI

struct PortfolioValueChart: View {
    @Query(sort: \PortfolioSnapshot.timestamp)
    private var snapshots: [PortfolioSnapshot]

    @State private var selectedRange: TimeRange = .oneMonth

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case oneYear = "1Y"
        case ytd = "YTD"

        var startDate: Date {
            let cal = Calendar.current
            let now = Date.now
            return switch self {
            case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
            case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
            case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
            case .ytd: cal.date(from: cal.dateComponents([.year], from: now))!
            }
        }
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        let start = selectedRange.startDate
        return snapshots.filter { $0.timestamp >= start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Time range picker
            Picker("Range", selection: $selectedRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            if filteredSnapshots.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see portfolio history")
                )
                .frame(height: 200)
            } else {
                Chart(filteredSnapshots, id: \.id) { snapshot in
                    AreaMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Value", snapshot.totalValue)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Value", snapshot.totalValue)
                    )
                    .foregroundStyle(Color.accentColor)

                    // Partial snapshot indicator
                    if snapshot.isPartial {
                        PointMark(
                            x: .value("Date", snapshot.timestamp),
                            y: .value("Value", snapshot.totalValue)
                        )
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
