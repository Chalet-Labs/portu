import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct AddPositionCategoryRuleTests {
    @Test func `manual asset category selection writes a global symbol rule`() throws {
        let fixture = try makeFixture()
        let context = fixture.context

        try ManualPositionCategoryRules.upsertGlobalRule(
            symbol: " aave ",
            categoryId: PortfolioCategoryDefaults.defiCategoryID,
            in: context)

        let rule = try #require(try fetchRules(context).first { $0.normalizedSymbol == "AAVE" })
        #expect(rule.category?.id == PortfolioCategoryDefaults.defiCategoryID)
    }

    @Test func `manual asset category selection updates existing global symbol rule`() throws {
        let fixture = try makeFixture()
        let context = fixture.context

        try ManualPositionCategoryRules.upsertGlobalRule(
            symbol: "aave",
            categoryId: PortfolioCategoryDefaults.defiCategoryID,
            in: context)
        try ManualPositionCategoryRules.upsertGlobalRule(
            symbol: "AAVE",
            categoryId: PortfolioCategoryDefaults.memeCategoryID,
            in: context)

        let rules = try fetchRules(context).filter { $0.normalizedSymbol == "AAVE" }
        #expect(rules.count == 1)
        #expect(rules.first?.category?.id == PortfolioCategoryDefaults.memeCategoryID)
    }

    @Test func `manual asset legacy category avoids default major bucket`() {
        #expect(ManualPositionCategoryRules.legacyCategory(for: PortfolioCategoryDefaults.categorySnapshots[0]) == .other)
        #expect(ManualPositionCategoryRules.legacyCategory(for: PortfolioCategoryDefaults.categorySnapshots[3]) == .defi)
        #expect(ManualPositionCategoryRules.legacyCategory(for: PortfolioCategoryDefaults.categorySnapshots[7]) == .stablecoin)
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
}
