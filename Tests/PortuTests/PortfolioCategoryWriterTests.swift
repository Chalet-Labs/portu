import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct PortfolioCategoryWriterTests {
    @Test func `renaming category saves the trimmed name`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let category = PortfolioCategory(name: "Original", sortOrder: 0)
        context.insert(category)
        try context.save()

        try PortfolioCategoryWriter.rename(
            category,
            to: "  Updated  ",
            in: context)

        #expect(category.name == "Updated")
    }

    @Test func `renaming category restores previous name when save fails`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let category = PortfolioCategory(name: "Original", sortOrder: 0)
        context.insert(category)
        try context.save()

        do {
            try PortfolioCategoryWriter.rename(
                category,
                to: "Updated",
                in: context) {
                    throw TestSaveError.expected
                }
            Issue.record("Expected category rename to rethrow the save failure.")
        } catch {
            #expect(category.name == "Original")
        }
    }

    private enum TestSaveError: Error {
        case expected
    }
}
