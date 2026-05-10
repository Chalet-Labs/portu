import Foundation
import PortuCore
import SwiftData

@MainActor
enum PortfolioCategorySeeder {
    static func seedIfNeeded(in context: ModelContext) throws {
        var categories = try context.fetch(FetchDescriptor<PortfolioCategory>())
        let shouldSeedDefaultRules = categories.isEmpty
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

        if shouldSeedDefaultRules {
            let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            for snapshot in PortfolioCategoryDefaults.symbolRuleSnapshots {
                guard let category = categoriesByID[snapshot.categoryId] else { continue }
                context.insert(CategorySymbolRule(
                    id: snapshot.id,
                    normalizedSymbol: snapshot.symbol,
                    category: category))
            }
        }

        try context.save()
    }
}
