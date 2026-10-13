import PortuCore
import SwiftData
import SwiftUI

/// The store's portfolio categories and symbol rules, for the Overview views that group by
/// category: the summary cards, the position tabs, the donut and Health. The other Overview views
/// do not read a category, so they do not hold these queries.
@MainActor
struct OverviewCategorySource: DynamicProperty {
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var categories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var rules: [CategorySymbolRule]

    var resolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: categories, rules: rules)
    }
}
