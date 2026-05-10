import Foundation
import PortuCore
import SwiftData

@MainActor
enum CategorySymbolRuleWriter {
    static func assign(
        symbol: String,
        to category: PortfolioCategory,
        existingRules: [CategorySymbolRule],
        in modelContext: ModelContext) throws {
        let normalizedSymbol = PortfolioCategoryDefaults.normalizeSymbol(symbol)
        guard !normalizedSymbol.isEmpty else { return }

        if let existing = existingRules.first(where: { $0.normalizedSymbol == normalizedSymbol }) {
            existing.category = category
        } else {
            modelContext.insert(CategorySymbolRule(normalizedSymbol: normalizedSymbol, category: category))
        }

        try modelContext.save()
    }
}
