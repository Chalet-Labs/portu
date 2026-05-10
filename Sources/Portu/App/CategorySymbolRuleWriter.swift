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
        try assign(
            symbol: symbol,
            to: category,
            existingRules: existingRules,
            in: modelContext) {
                try modelContext.save()
            }
    }

    static func assign(
        symbol: String,
        to category: PortfolioCategory,
        existingRules: [CategorySymbolRule],
        in modelContext: ModelContext,
        save: () throws -> Void) throws {
        let normalizedSymbol = PortfolioCategoryDefaults.normalizeSymbol(symbol)
        guard !normalizedSymbol.isEmpty else { return }

        let existingRule = existingRules.first(where: { $0.normalizedSymbol == normalizedSymbol })
        let previousCategory = existingRule?.category
        let inserted: CategorySymbolRule?
        if let existing = existingRule {
            existing.category = category
            inserted = nil
        } else {
            let rule = CategorySymbolRule(normalizedSymbol: normalizedSymbol, category: category)
            modelContext.insert(rule)
            inserted = rule
        }

        do {
            try save()
        } catch {
            if let inserted { modelContext.delete(inserted) }
            if let existingRule { existingRule.category = previousCategory }
            throw error
        }
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
