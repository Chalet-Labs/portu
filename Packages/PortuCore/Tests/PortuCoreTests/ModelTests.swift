import Foundation
import Testing
import SwiftData
@testable import PortuCore

@Suite("SwiftData Model Tests")
struct ModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Portfolio.self, Account.self, Holding.self, Asset.self,
            configurations: config
        )
        context = container.mainContext
    }

    @Test func portfolioCreation() throws {
        let portfolio = Portfolio(name: "Main")
        context.insert(portfolio)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Portfolio>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Main")
    }

    @Test func accountRelationship() throws {
        let portfolio = Portfolio(name: "Main")
        let account = Account(name: "Binance", kind: .exchange)
        account.exchangeType = .binance
        account.portfolio = portfolio
        portfolio.accounts.append(account)

        context.insert(portfolio)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Portfolio>())
        #expect(fetched.first?.accounts.count == 1)
        #expect(fetched.first?.accounts.first?.kind == .exchange)
        #expect(fetched.first?.accounts.first?.exchangeType == .binance)
    }

    @Test func holdingAssetRelationship() throws {
        let asset = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin")
        let holding = Holding(amount: 1.5, costBasis: 60000)
        holding.asset = asset

        context.insert(asset)
        context.insert(holding)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Holding>())
        #expect(fetched.first?.asset?.symbol == "BTC")
        #expect(fetched.first?.amount == 1.5)
    }

    @Test func cascadeDeletePortfolioRemovesAccounts() throws {
        let portfolio = Portfolio(name: "Main")
        let account = Account(name: "Manual", kind: .manual)
        account.portfolio = portfolio
        portfolio.accounts.append(account)

        context.insert(portfolio)
        try context.save()

        context.delete(portfolio)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.isEmpty)
    }

    @Test func accountKindFilterAndFetch() throws {
        let portfolio = Portfolio(name: "Main")
        let manual = Account(name: "Manual", kind: .manual)
        let exchange = Account(name: "Binance", kind: .exchange)
        manual.portfolio = portfolio
        exchange.portfolio = portfolio
        portfolio.accounts.append(contentsOf: [manual, exchange])

        context.insert(portfolio)
        try context.save()

        // Fetch all accounts and verify enum-based filtering works correctly.
        // SwiftData stores RawRepresentable enums by raw value; predicates on
        // custom enums require in-memory filtering or raw-value workarounds.
        let all = try context.fetch(FetchDescriptor<Account>())
        #expect(all.count == 2)

        let exchanges = all.filter { $0.kind == .exchange }
        #expect(exchanges.count == 1)
        #expect(exchanges.first?.name == "Binance")

        let manuals = all.filter { $0.kind == .manual }
        #expect(manuals.count == 1)
        #expect(manuals.first?.name == "Manual")
    }
}
