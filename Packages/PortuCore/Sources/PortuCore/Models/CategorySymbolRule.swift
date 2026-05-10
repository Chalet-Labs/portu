import Foundation
import SwiftData

@Model
public final class CategorySymbolRule {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var normalizedSymbol: String
    public var category: PortfolioCategory?

    public init(
        id: UUID = UUID(),
        normalizedSymbol: String,
        category: PortfolioCategory? = nil) {
        self.id = id
        self.normalizedSymbol = PortfolioCategoryDefaults.normalizeSymbol(normalizedSymbol)
        self.category = category
    }
}

public struct CategorySymbolRuleSnapshot: Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let symbol: String
    public let categoryId: UUID

    public init(
        id: UUID,
        symbol: String,
        categoryId: UUID) {
        self.id = id
        self.symbol = PortfolioCategoryDefaults.normalizeSymbol(symbol)
        self.categoryId = categoryId
    }

    public init?(_ rule: CategorySymbolRule) {
        guard let category = rule.category else { return nil }
        self.init(
            id: rule.id,
            symbol: rule.normalizedSymbol,
            categoryId: category.id)
    }
}
