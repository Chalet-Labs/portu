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
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var filtered: [AssetSnapshot] {
        snapshots.filter { snap in
            snap.timestamp >= startDate
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
        let entries: [CategorySnapshotEntry] = filtered.compactMap { snapshot in
            let entry = CategorySnapshotEntry(snapshot: snapshot)
            guard !store.performance.disabledPortfolioCategoryIDs.contains(entry.categoryID) else { return nil }
            return entry
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
                ForEach(categoryResolver.categories) { cat in
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
