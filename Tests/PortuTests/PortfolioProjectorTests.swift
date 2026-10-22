import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// The projector against today's in-view pipeline (#123, spec P1–P4, B2). One in-memory store holds
/// an active wallet (ETH idle, a manually priced and an ignored token, a mapped onchain token, an
/// empty lending position), an inactive wallet (BTC), the user's categories with a DEGEN →
/// Stablecoins rule, and historical rows inside and outside the window, USD and CHF.
@MainActor
struct PortfolioProjectorTests {
    private typealias Fixture = PortfolioValuationFixture

    /// 2025-10-06 12:00 UTC: the window starts 2025-10-04.
    private static let now = Fixture.noon(0)
    private static let degenContract = "0xde9e000000000000000000000000000000000de9"

    @Test func `the projection equals today's in-view pipeline`() async throws {
        let store = try Self.seededStore()

        let projection = try await Self.build(store.container)

        let context = store.container.mainContext
        let positions = try context.fetch(FetchDescriptor<Position>())
        let tokens = try context.fetch(FetchDescriptor<PositionToken>())
        let overrides = try context.fetch(FetchDescriptor<TokenPricingOverride>()).map(TokenPricingOverrideSnapshot.init)
        let mappings = try context.fetch(FetchDescriptor<TokenIdentityMapping>()).map(TokenIdentityMappingSnapshot.init)
        let resolver = try PortfolioCategoryResolver.live(
            categories: context.fetch(FetchDescriptor<PortfolioCategory>(sortBy: [
                SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)
            ])),
            rules: context.fetch(FetchDescriptor<CategorySymbolRule>(sortBy: [SortDescriptor(\CategorySymbolRule.normalizedSymbol)])))
        let headline = ActivePortfolioProjection(positions, categoryResolver: resolver)
        let windowStart = MarketPrices.closeWindowStart(now: Self.now)
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>(
            predicate: #Predicate { $0.day >= windowStart },
            sortBy: [SortDescriptor(\HistoricalPricePoint.day), SortDescriptor(\HistoricalPricePoint.coinGeckoId)]))

        #expect(resolver != .defaults, "the store's categories must differ from the defaults")
        #expect(projection.holdings == PortfolioValuation.prepare(headline.inputs, overrides: overrides, mappings: mappings))
        #expect(projection.positionGroups == headline.cards)
        #expect(projection.pollingCandidates == PortfolioValuation.prepare(
            ValuationInput.activeAccounts(tokens, categoryResolver: .defaults),
            overrides: overrides,
            mappings: mappings))
        #expect(projection.historical == HistoricalMarketPricesFeature.prices(from: rows, isBackfillEnabled: true, now: Self.now))
        #expect(projection.overrides == overrides)
        #expect(projection.mappings == mappings)
    }

    @Test func `the projection holds the store's categories, mappings and overrides already resolved`() async throws {
        let store = try Self.seededStore()

        let projection = try await Self.build(store.container)

        let bySymbol = Dictionary(uniqueKeysWithValues: projection.holdings.map { ($0.input.token.symbol, $0) })
        #expect(bySymbol["DEGEN"]?.input.token.portfolioCategory.name == "Stablecoins", "the store's DEGEN rule applies to holdings")
        #expect(bySymbol["DEGEN"]?.priceID == "degen-base", "the identity mapping is applied")
        #expect(bySymbol["MNL"]?.priceID == nil, "a manual price needs no price ID")
        #expect(bySymbol["MNL"]?.override?.manualPriceUSD == 7)
        #expect(bySymbol["SCAM"]?.override?.isIgnored == true)
        let candidateDegen = projection.pollingCandidates.first { $0.input.token.symbol == "DEGEN" }
        #expect(candidateDegen?.input.token.portfolioCategory.name != "Stablecoins", "candidates use the default rules")
        #expect(candidateDegen?.input.token.usdValue == 95, "candidates carry their sync-time value")
    }

    @Test func `inactive accounts are excluded from every list but the account index`() async throws {
        let store = try Self.seededStore()

        let projection = try await Self.build(store.container)

        let symbols = Set(projection.holdings.map(\.input.token.symbol) + projection.pollingCandidates.map(\.input.token.symbol))
        #expect(!symbols.contains("BTC"))
        #expect(symbols == ["ETH", "MNL", "SCAM", "DEGEN"])
        #expect(projection.positionGroups.count == 2, "the active wallet and its empty lending position")
        #expect(projection.accounts[store.inactiveID]?.isActive == false)
        #expect(projection.accounts[store.inactiveID]?.name == "Old Wallet")
        #expect(projection.accounts[store.activeID]?.isActive == true)
        #expect(projection.assets.count == 5, "every asset, held or not")
        #expect(projection.assets.values.contains { $0.symbol == "BTC" && $0.coinGeckoId == "bitcoin" })
    }

    @Test func `the historical book keeps usd rows in the window and drops the rest`() async throws {
        let store = try Self.seededStore()

        let projection = try await Self.build(store.container)

        #expect(projection.historical.closesUSD["ethereum"]?.price == 3000)
        #expect(projection.historical.closesUSD["ethereum"]?.day == Fixture.day(0))
        #expect(projection.historical.changes24h["ethereum"] == Fixture.decimal("0.2"), "3000 over yesterday's 2500")
        #expect(projection.historical.closesUSD["chainlink"] == nil, "a CHF row is dropped, never converted")
        #expect(projection.historical.closesUSD["bitcoin"] == nil, "a row before the window is left out")
    }

    @Test func `with backfill disabled the historical book is empty`() async throws {
        let store = try Self.seededStore()

        let projection = try await Self.build(store.container, isBackfillEnabled: false)

        #expect(projection.historical == .empty)
        #expect(!projection.holdings.isEmpty)
    }

    @Test func `a category rule change shows in the next build`() async throws {
        let store = try Self.seededStore()
        let context = store.container.mainContext
        let before = try await Self.build(store.container)

        for rule in try context.fetch(FetchDescriptor<CategorySymbolRule>()) where rule.normalizedSymbol == "DEGEN" {
            context.delete(rule)
        }
        try context.save()
        let after = try await Self.build(store.container)

        let category = { (projection: PortfolioProjection) in
            projection.holdings.first { $0.input.token.symbol == "DEGEN" }?.input.token.portfolioCategory.name
        }
        #expect(category(before) == "Stablecoins")
        #expect(category(after) != "Stablecoins")
        #expect(before != after)
    }

    @Test func `two builds from unchanged rows are equal`() async throws {
        let store = try Self.seededStore()

        let first = try await Self.build(store.container)
        let second = try await Self.build(store.container)

        #expect(first == second)
    }

    @Test func `the projection outlives deletion of its source models`() async throws {
        let store = try Self.seededStore()
        let projection = try await Self.build(store.container)
        let context = store.container.mainContext

        for position in try context.fetch(FetchDescriptor<Position>()) {
            context.delete(position)
        }
        try context.save()

        #expect(projection.holdings.map(\.input.token.symbol).sorted() == ["DEGEN", "ETH", "MNL", "SCAM"])
        #expect(projection.positionGroups.count == 2)
    }

    @Test func `the client factory keeps the projector off the main thread`() async throws {
        let store = try Self.seededStore()
        let projector = await PortfolioProjectorClient.makeProjector(modelContainer: store.container)

        #expect(await projector.isExecutingOnMainThread() == false)
    }

    // MARK: - Fixture

    private static func build(_ container: ModelContainer, isBackfillEnabled: Bool = true) async throws -> PortfolioProjection {
        let projector = await PortfolioProjectorClient.makeProjector(modelContainer: container)
        return try await projector.build(PortfolioProjectionRequest(isHistoricalBackfillEnabled: isBackfillEnabled, now: now))
    }

    struct Store {
        let container: ModelContainer
        let activeID: UUID
        let inactiveID: UUID
    }

    private static func seededStore() throws -> Store {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        try PortfolioCategorySeeder.seedIfNeeded(in: context)

        let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        let manual = Asset(symbol: "MNL", name: "Manual", coinGeckoId: "manual-coin", category: .other)
        let scam = Asset(symbol: "SCAM", name: "Scam", coinGeckoId: "scam", category: .meme)
        let degen = Asset(symbol: "DEGEN", name: "Degen", upsertChain: .degen, upsertContract: degenContract, category: .meme)
        let btc = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major)
        let active = Account(name: "Active Wallet", kind: .wallet, dataSource: .zerion)
        let inactive = Account(name: "Old Wallet", kind: .wallet, dataSource: .zerion, isActive: false)
        let syncedAt = Fixture.noon(-1)
        active.positions = [
            Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 6000,
                tokens: [
                    PositionToken(role: .balance, amount: 2, usdValue: 5800, asset: eth),
                    PositionToken(role: .balance, amount: 10, usdValue: 50, asset: manual),
                    PositionToken(role: .balance, amount: 1000, usdValue: 10, asset: scam),
                    PositionToken(role: .balance, amount: 10000, usdValue: 95, asset: degen)
                ],
                account: active,
                syncedAt: syncedAt),
            Position(positionType: .lending, protocolId: "aave-v3", protocolName: "Aave V3", account: active, syncedAt: syncedAt)
        ]
        inactive.positions = [
            Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 60000,
                tokens: [PositionToken(role: .balance, amount: 1, usdValue: 60000, asset: btc)],
                account: inactive,
                syncedAt: syncedAt)
        ]
        for model in [eth, manual, scam, degen, btc] {
            context.insert(model)
        }
        context.insert(active)
        context.insert(inactive)
        context.insert(TokenIdentityMapping(chain: .degen, contractAddress: degenContract, coinGeckoId: "degen-base"))
        context.insert(TokenPricingOverride(assetId: manual.id, manualPriceUSD: 7))
        context.insert(TokenPricingOverride(assetId: scam.id, isIgnored: true))
        let stablecoins = try #require(try context.fetch(FetchDescriptor<PortfolioCategory>()).first { $0.name == "Stablecoins" })
        context.insert(CategorySymbolRule(normalizedSymbol: "DEGEN", category: stablecoins))
        context.insert(HistoricalPricePoint(coinGeckoId: "ethereum", day: Fixture.day(0), currency: .usd, price: 3000))
        context.insert(HistoricalPricePoint(coinGeckoId: "ethereum", day: Fixture.day(-1), currency: .usd, price: 2500))
        context.insert(HistoricalPricePoint(coinGeckoId: "chainlink", day: Fixture.day(0), currency: .chf, price: 12))
        context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Fixture.day(-5), currency: .usd, price: 60000))
        try context.save()
        return Store(container: container, activeID: active.id, inactiveID: inactive.id)
    }
}
