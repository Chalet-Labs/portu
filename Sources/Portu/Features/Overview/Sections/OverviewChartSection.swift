import SwiftUI
import Charts
import PortuCore
import PortuUI

struct OverviewChartSection: View {
    let viewModel: OverviewViewModel
    @State private var selectedRange: TimeRangePicker.Range = .oneMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                SectionHeader(
                    "Portfolio Value",
                    subtitle: "Historical snapshots from completed sync runs"
                )

                Spacer()

                TimeRangePicker(selection: $selectedRange)
                    .frame(maxWidth: 320)
            }

            if filteredSnapshots.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                    .frame(height: 220)
                    .overlay {
                        Text("Sync to start building portfolio history.")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Chart(filteredSnapshots) { snapshot in
                    AreaMark(
                        x: .value("Timestamp", snapshot.timestamp),
                        y: .value("Portfolio Value", doubleValue(snapshot.totalValue))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Timestamp", snapshot.timestamp),
                        y: .value("Portfolio Value", doubleValue(snapshot.totalValue))
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 220)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var filteredSnapshots: [PortfolioSnapshot] {
        let cutoffDate = cutoffDate(for: selectedRange)
        return viewModel.snapshots.filter { $0.timestamp >= cutoffDate }
    }

    private func cutoffDate(for range: TimeRangePicker.Range) -> Date {
        let calendar = Calendar.current
        let now = Date.now

        switch range {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .yearToDate:
            return calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        }
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
