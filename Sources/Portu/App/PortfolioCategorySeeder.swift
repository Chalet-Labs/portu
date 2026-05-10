import Foundation
import PortuCore
import SwiftData

@MainActor
enum PortfolioCategorySeeder {
    static func seedIfNeeded(in context: ModelContext) throws {
        var categories = try context.fetch(FetchDescriptor<PortfolioCategory>())
        if categories.isEmpty {
            categories = PortfolioCategoryDefaults.categorySnapshots.map { snapshot in
                PortfolioCategory(
                    id: snapshot.id,
                    name: snapshot.name,
                    sortOrder: snapshot.sortOrder,
                    semanticRole: snapshot.semanticRole,
                    isSystemRequired: snapshot.isSystemRequired)
            }
            for category in categories {
                context.insert(category)
            }
        }

        let rules = try context.fetch(FetchDescriptor<CategorySymbolRule>())
        let existingSymbols = Set(rules.map { PortfolioCategoryDefaults.normalizeSymbol($0.normalizedSymbol) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for snapshot in PortfolioCategoryDefaults.symbolRuleSnapshots {
            guard !existingSymbols.contains(snapshot.symbol) else { continue }
            guard let category = categoriesByID[snapshot.categoryId] else { continue }
            context.insert(CategorySymbolRule(
                id: snapshot.id,
                normalizedSymbol: snapshot.symbol,
                category: category))
        }

        try context.save()
    }
}
