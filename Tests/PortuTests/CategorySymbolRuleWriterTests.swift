import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct CategorySymbolRuleWriterTests {
    @Test func `assigning category inserts a normalized symbol rule`() throws {
        let fixture = try makeFixture()
        let category = try PortfolioCategory(
            id: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
            name: "ETH",
            sortOrder: 0)
        fixture.context.insert(category)
        try fixture.context.save()

        try CategorySymbolRuleWriter.assign(
            symbol: " usdc.e ",
            to: category,
            existingRules: [],
            in: fixture.context)

        let rules = try fetchRules(fixture.context)
        let rule = try #require(rules.first)
        #expect(rule.normalizedSymbol == "USDCE")
        #expect(rule.category?.id == category.id)
    }

    @Test func `assigning category moves an existing symbol rule`() throws {
        let fixture = try makeFixture()
        let oldCategory = try PortfolioCategory(
            id: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
            name: "Stablecoins",
            sortOrder: 0,
            semanticRole: .stablecoin)
        let newCategory = try PortfolioCategory(
            id: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
            name: "Majors",
            sortOrder: 1)
        let rule = CategorySymbolRule(normalizedSymbol: "ETH", category: oldCategory)
        fixture.context.insert(oldCategory)
        fixture.context.insert(newCategory)
        fixture.context.insert(rule)
        try fixture.context.save()

        try CategorySymbolRuleWriter.assign(
            symbol: "eth",
            to: newCategory,
            existingRules: [rule],
            in: fixture.context)

        let rules = try fetchRules(fixture.context)
        #expect(rules.count == 1)
        #expect(rules.first?.normalizedSymbol == "ETH")
        #expect(rules.first?.category?.id == newCategory.id)
    }

    @Test func `removing symbol rule restores it when save fails`() throws {
        let fixture = try makeFixture()
        let category = try PortfolioCategory(
            id: #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")),
            name: "ETH",
            sortOrder: 0)
        let rule = CategorySymbolRule(normalizedSymbol: "ETH", category: category)
        fixture.context.insert(category)
        fixture.context.insert(rule)
        try fixture.context.save()

        do {
            try CategorySymbolRuleWriter.remove(rule, in: fixture.context) {
                throw TestSaveError.expected
            }
            Issue.record("Expected removing the rule to rethrow the save failure.")
        } catch {
            let rules = try fetchRules(fixture.context)
            #expect(rules.contains { $0.id == rule.id && $0.normalizedSymbol == "ETH" })
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory().makeInMemory()
        return Fixture(container: container, context: container.mainContext)
    }

    private func fetchRules(_ context: ModelContext) throws -> [CategorySymbolRule] {
        try context.fetch(FetchDescriptor<CategorySymbolRule>(sortBy: [SortDescriptor(\.normalizedSymbol)]))
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
    }

    private enum TestSaveError: Error {
        case expected
    }
}
