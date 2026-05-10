import Foundation
import PortuCore
import SwiftData

@MainActor
enum PortfolioCategoryWriter {
    enum WriterError: LocalizedError, Equatable {
        case missingFallbackCategory

        var errorDescription: String? {
            switch self {
            case .missingFallbackCategory:
                "Cannot delete category because the fallback category is missing."
            }
        }
    }

    static func rename(
        _ category: PortfolioCategory,
        to name: String,
        in modelContext: ModelContext) throws {
        try rename(category, to: name, in: modelContext) {
            try modelContext.save()
        }
    }

    static func rename(
        _ category: PortfolioCategory,
        to name: String,
        in _: ModelContext,
        save: () throws -> Void) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousName = category.name
        guard !trimmedName.isEmpty else { return }
        guard trimmedName != previousName else { return }

        category.name = trimmedName
        do {
            try save()
        } catch {
            category.name = previousName
            throw error
        }
    }

    static func delete(
        _ category: PortfolioCategory,
        fallbackCategory: PortfolioCategory?,
        rules: [CategorySymbolRule],
        in modelContext: ModelContext) throws {
        try delete(
            category,
            fallbackCategory: fallbackCategory,
            rules: rules,
            in: modelContext) {
                try modelContext.save()
            }
    }

    static func delete(
        _ category: PortfolioCategory,
        fallbackCategory: PortfolioCategory?,
        rules: [CategorySymbolRule],
        in modelContext: ModelContext,
        save: () throws -> Void) throws {
        guard !category.isSystemRequired else { return }
        guard let fallbackCategory else {
            throw WriterError.missingFallbackCategory
        }

        let originalAssignments = rules.map { (rule: $0, category: $0.category) }
        for rule in rules {
            rule.category = fallbackCategory
        }

        modelContext.delete(category)
        do {
            try save()
        } catch {
            for assignment in originalAssignments {
                assignment.rule.category = assignment.category
            }
            modelContext.insert(category)
            throw error
        }
    }
}
