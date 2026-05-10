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

    static func remove(_ rule: CategorySymbolRule, in modelContext: ModelContext) throws {
        try remove(rule, in: modelContext) {
            try modelContext.save()
        }
    }

    static func remove(
        _ rule: CategorySymbolRule,
        in modelContext: ModelContext,
        save: () throws -> Void) throws {
        let id = rule.id
        let normalizedSymbol = rule.normalizedSymbol
        let category = rule.category
        modelContext.delete(rule)
        do {
            try save()
        } catch {
            modelContext.insert(CategorySymbolRule(
                id: id,
                normalizedSymbol: normalizedSymbol,
                category: category))
            throw error
        }
    }
}
