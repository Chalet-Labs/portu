import Charts
import PortuCore
import SwiftData
import SwiftUI

struct ValueChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \PortfolioSnapshot.timestamp)
    private var portfolioSnapshots: [PortfolioSnapshot]

    @Query(sort: \AccountSnapshot.timestamp)
    private var accountSnapshots: [AccountSnapshot]

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

    var body: some View {
        if dataPoints.isEmpty {
            ContentUnavailableView(
                "No Performance Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Sync your accounts to track portfolio performance")
            )
            .frame(height: 300)
        } else {
            Chart {
                ForEach(dataPoints, id: \.0) { date, value, isPartial in
                    AreaMark(x: .value("Date", date), y: .value("Value", value))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Color.accentColor.opacity(0.3), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("Date", date), y: .value("Value", value))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(isPartial ? StrokeStyle(lineWidth: 2, dash: [5, 3]) : StrokeStyle(lineWidth: 2))
                }
            }
            .chartYAxis {
                AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
            }
            .frame(height: 300)
            .padding()
        }
    }
}
