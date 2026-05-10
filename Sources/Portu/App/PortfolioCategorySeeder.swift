import Foundation
import PortuCore
import SwiftData

@MainActor
enum PortfolioCategorySeeder {
    static func seedIfNeeded(in context: ModelContext) throws {
        try seedIfNeeded(in: context) {
            try context.save()
        }
    }

    static func seedIfNeeded(in context: ModelContext, save: () throws -> Void) throws {
        var didChange = false
        var categories = try context.fetch(FetchDescriptor<PortfolioCategory>())
        let rules = try context.fetch(FetchDescriptor<CategorySymbolRule>())
        let shouldSeedDefaultRules = rules.isEmpty
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
            didChange = true
        }

        let defaultCategoriesByID = Dictionary(uniqueKeysWithValues: PortfolioCategoryDefaults.categorySnapshots.map { ($0.id, $0) })
        for category in categories {
            guard let defaultCategory = defaultCategoriesByID[category.id], defaultCategory.isSystemRequired else { continue }
            if !category.isSystemRequired {
                category.isSystemRequired = true
                didChange = true
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
                didChange = true
            }
        }

        if didChange {
            try save()
        }
    }
}
