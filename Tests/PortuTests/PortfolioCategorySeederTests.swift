import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct PortfolioCategorySeederTests {
    @Test func `seeding inserts default categories and symbol rules once`() throws {
        let fixture = try makeFixture()
        let context = fixture.context

        try PortfolioCategorySeeder.seedIfNeeded(in: context)
        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        let categories = try fetchCategories(context)
        let rules = try fetchRules(context)

        #expect(categories.map(\.name) == [
            "BTC",
            "ETH",
            "SOL",
            "DeFi",
            "Meme",
            "Privacy",
            "Fiat",
            "Stablecoins",
            "Other Tokens"
        ])
        #expect(categories.map(\.name).contains("SUI") == false)
        #expect(rules.map(\.normalizedSymbol).sorted() == PortfolioCategoryDefaults.symbolRuleSnapshots.map(\.symbol).sorted())
    }

    @Test func `seeding does not reset user edits`() throws {
        let fixture = try makeFixture()
        let context = fixture.context

        try PortfolioCategorySeeder.seedIfNeeded(in: context)
        let btc = try #require(try fetchCategories(context).first { $0.id == PortfolioCategoryDefaults.btcCategoryID })
        btc.name = "Majors"
        btc.sortOrder = 42
        try context.save()

        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        let edited = try #require(try fetchCategories(context).first { $0.id == PortfolioCategoryDefaults.btcCategoryID })
        #expect(edited.name == "Majors")
        #expect(edited.sortOrder == 42)
    }

    @Test func `seeding preserves removed default symbol rules`() throws {
        let fixture = try makeFixture()
        let context = fixture.context

        try PortfolioCategorySeeder.seedIfNeeded(in: context)
        let ethRule = try #require(try fetchRules(context).first { $0.normalizedSymbol == "ETH" })
        context.delete(ethRule)
        try context.save()

        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        let rules = try fetchRules(context)
        #expect(rules.contains { $0.normalizedSymbol == "ETH" } == false)
    }

    @Test func `seeding preserves existing symbol assignments when categories already exist`() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let categories = PortfolioCategoryDefaults.categorySnapshots.map { snapshot in
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
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let btc = try #require(categoriesByID[PortfolioCategoryDefaults.btcCategoryID])
        let eth = try #require(categoriesByID[PortfolioCategoryDefaults.ethCategoryID])
        try context.insert(CategorySymbolRule(
            id: #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")),
            normalizedSymbol: "USDC",
            category: btc))
        context.insert(CategorySymbolRule(normalizedSymbol: "ETH", category: eth))
        try context.save()

        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        let rules = try fetchRules(context)
        #expect(Set(rules.map(\.normalizedSymbol)) == ["ETH", "USDC"])
        #expect(rules.count(where: { $0.normalizedSymbol == "USDC" }) == 1)
        #expect(rules.first { $0.normalizedSymbol == "USDC" }?.category?.id == PortfolioCategoryDefaults.btcCategoryID)
    }

    @Test func `seeding inserts default symbol rules when categories already exist without rules`() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let categories = PortfolioCategoryDefaults.categorySnapshots.map { snapshot in
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
        try context.save()

        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        let rules = try fetchRules(context)
        #expect(rules.map(\.normalizedSymbol).sorted() == PortfolioCategoryDefaults.symbolRuleSnapshots.map(\.symbol).sorted())
    }

    @Test func `seeding marks existing default stablecoin category as system required`() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let stablecoins = PortfolioCategory(
            id: PortfolioCategoryDefaults.stablecoinsCategoryID,
            name: "Stablecoins",
            sortOrder: 7,
            semanticRole: .stablecoin,
            isSystemRequired: false)
        context.insert(stablecoins)
        try context.save()

        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        #expect(stablecoins.isSystemRequired)
    }

    @Test func `seeding skips save when defaults already exist`() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        try PortfolioCategorySeeder.seedIfNeeded(in: context) {
            throw TestSaveError.expected
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory().makeInMemory()
        return Fixture(container: container, context: container.mainContext)
    }

    private func fetchCategories(_ context: ModelContext) throws -> [PortfolioCategory] {
        try context.fetch(FetchDescriptor<PortfolioCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
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
