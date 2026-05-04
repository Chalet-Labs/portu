import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AssetsChartMode: View {
    let accountId: UUID?
    let startDate: Date
    let store: StoreOf<AppFeature>

    @Query(sort: \AssetSnapshot.timestamp)
    private var snapshots: [AssetSnapshot]

    private var filtered: [AssetSnapshot] {
        snapshots.filter { snap in
            snap.timestamp >= startDate
                && !store.performance.disabledCategories.contains(snap.category)
                && (accountId == nil || snap.accountId == accountId)
        }
    }

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let value: Decimal
    }

    private var chartData: [ChartPoint] {
        let entries = filtered.map {
            CategorySnapshotEntry(
                accountId: $0.accountId, assetId: $0.assetId,
                timestamp: $0.timestamp, category: $0.category, usdValue: $0.usdValue)
        }
        return PerformanceFeature.aggregateCategorySnapshots(entries: entries)
            .map { ChartPoint(date: $0.date, category: $0.category, value: $0.value) }
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
                Chart(chartData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        stacking: .standard)
                        .foregroundStyle(by: .value("Category", point.category))
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 320)
            }

            HStack(spacing: 8) {
                ForEach(AssetCategory.allCases, id: \.self) { cat in
                    Button {
                        store.send(.performance(.categoryToggled(cat)))
                    } label: {
                        Text(cat.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                store.performance.disabledCategories.contains(cat)
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
