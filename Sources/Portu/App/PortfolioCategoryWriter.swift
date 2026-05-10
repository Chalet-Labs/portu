import Foundation
import PortuCore
import SwiftData

@MainActor
enum PortfolioCategoryWriter {
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
}
