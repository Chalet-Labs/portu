import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PerformanceBottomPanel: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp) private var snapshots: [AssetSnapshot]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var categoryChanges: [CategoryChange] {
        let resolver = categoryResolver
        let entries = snapshots
            .filter { s in
                s.timestamp >= startDate && (accountId == nil || s.accountId == accountId)
            }
            .map { CategorySnapshotEntry(snapshot: $0, categoryResolver: resolver) }
        return PerformanceFeature.computeCategoryChanges(entries: entries)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset categories")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                ForEach(categoryChanges) { change in
                    HStack {
                        Text(change.name).frame(width: 100, alignment: .leading)
                        Text(change.startValue, format: .currency(code: "USD")).frame(width: 100)
                        Text("\u{2192}").foregroundStyle(PortuTheme.dashboardSecondaryText)
                        Text(change.endValue, format: .currency(code: "USD")).frame(width: 100)
                        Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(change.percentChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                            .frame(width: 60)
                    }
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Asset prices")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                Text("Top assets with period price change")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }
        }
        .frame(minHeight: 180, alignment: .topLeading)
    }
}
