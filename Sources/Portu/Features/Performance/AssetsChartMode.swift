import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

/// Passive renderer: every point and category arrives pre-shaped from
/// `PerformanceFeature.State`, which is filled off the main actor by
/// `PerformanceDataClient`. No SwiftData query, no aggregation, no environment
/// state — so no body evaluation can fault models or rebuild a category resolver.
struct AssetsChartMode: View {
    let categories: [PortfolioCategorySnapshot]
    let chartData: [CategoryChartPoint]
    let store: StoreOf<AppFeature>

    private var currencyCode: String {
        store.selectedCurrency.displayCode
    }

    var body: some View {
        VStack(spacing: 8) {
            if chartData.isEmpty {
                ContentUnavailableView(
                    "No Asset Data", systemImage: "chart.bar.xaxis",
                    description: Text("Sync to see asset category breakdown"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 320)
            } else {
                // One point per (UTC day, category) upstream, so the value itself is a
                // stable identity.
                Chart(chartData, id: \.self) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        stacking: .standard)
                        .foregroundStyle(by: .value("Category", point.categoryID))
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: currencyCode).precision(.fractionLength(0)))
                }
                .frame(height: 320)
            }

            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    Button {
                        store.send(.performance(.portfolioCategoryToggled(cat.id.uuidString)))
                    } label: {
                        Text(cat.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                store.performance.disabledPortfolioCategoryIDs.contains(cat.id.uuidString)
                                    ? AnyShapeStyle(PortuTheme.dashboardMutedPanelBackground)
                                    : AnyShapeStyle(PortuTheme.dashboardGoldMuted))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PortuTheme.dashboardText)
                }
            }
        }
    }
}
