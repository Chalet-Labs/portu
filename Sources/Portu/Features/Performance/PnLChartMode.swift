import SwiftUI
import SwiftData
import Charts
import PortuCore

struct PnLChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnaps: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnaps: [AccountSnapshot]

    @State private var showCumulative = false

    private struct PnLBar: Identifiable {
        let id = UUID()
        let date: Date
        let pnl: Decimal
        let cumulative: Decimal
    }

    private var bars: [PnLBar] {
        // Get daily totals
        let dailyValues: [(Date, Decimal)]
        if let accountId {
            let filtered = accountSnaps.filter { $0.accountId == accountId && $0.timestamp >= startDate }
            dailyValues = lastPerDay(filtered.map { ($0.timestamp, $0.totalValue) })
        } else {
            let filtered = portfolioSnaps.filter { $0.timestamp >= startDate }
            dailyValues = lastPerDay(filtered.map { ($0.timestamp, $0.totalValue) })
        }

        guard dailyValues.count >= 2 else { return [] }

        var result: [PnLBar] = []
        var cumulative: Decimal = 0
        for i in 1..<dailyValues.count {
            let pnl = dailyValues[i].1 - dailyValues[i-1].1
            cumulative += pnl
            result.append(PnLBar(date: dailyValues[i].0, pnl: pnl, cumulative: cumulative))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            if bars.isEmpty {
                ContentUnavailableView("Insufficient Data", systemImage: "chart.bar",
                                       description: Text("Need at least 2 days of data for PnL"))
                    .frame(height: 300)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: .day),
                        y: .value("PnL", bar.pnl)
                    )
                    .foregroundStyle(bar.pnl >= 0 ? Color.green : Color.red)

                    if showCumulative {
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

            Toggle("Show Cumulative", isOn: $showCumulative)
                .padding(.horizontal)
        }
    }

    /// Keep last snapshot per day
    private func lastPerDay(_ values: [(Date, Decimal)]) -> [(Date, Decimal)] {
        let cal = Calendar.current
        var byDay: [DateComponents: (Date, Decimal)] = [:]
        for (date, value) in values {
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            if let existing = byDay[comps] {
                if date > existing.0 { byDay[comps] = (date, value) }
            } else {
                byDay[comps] = (date, value)
            }
        }
        return byDay.values.sorted { $0.0 < $1.0 }
    }
}
