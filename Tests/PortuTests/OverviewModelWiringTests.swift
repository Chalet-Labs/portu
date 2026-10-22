import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// What the portfolio read model values from a real store for the Overview panels (#123, #124): the
/// projector projects the store's models (identity mappings, override rows, categories and rules)
/// and the valuator values that projection, so these pin the shared headline input (top bar and
/// Sidebar header), the cards input, the Health input and the polling IDs. One store, in memory:
///
/// | Token | Account | Amount | `usdValue` | USD value |
/// |---|---|---|---|---|
/// | ETH | active | 2 | 5800 | 6000 (live 3000, 24h +25% from the live changes only) |
/// | DEGEN | active | 10,000 | 95 | 100 (Degen-chain token mapped to `degen-base`, live 0.01; sync 95) |
/// | BTC | inactive | 1 | 60000 | not valued |
///
/// The rate is 0.9.
@MainActor
struct OverviewModelWiringTests {
    private typealias Fixture = PortfolioValuationFixture

    private static let degenContract = "0xde9e000000000000000000000000000000000de9"
    static let rate = Fixture.decimal("0.9")

    @Test func `the active portfolio headline values the usd book with mappings and live changes`() async throws {
        let store = try Store()

        let headline = try await Self.readModel(store).valued.headline

        #expect(headline.total == 6100 * Self.rate)
        #expect(headline.change24h == 1200 * Self.rate)
        #expect(headline.changePercentage == Decimal(1200) / Decimal(4900))
    }

    @Test func `cards value a mapped token through its identity mapping`() async throws {
        let store = try Store()

        let cards = try await Self.readModel(store).overview.summaryCards
        let idle = try #require(cards.first { $0.title == "Idle" })

        #expect(idle.rows.map(\.value) == [0, 6000 * Self.rate, 100 * Self.rate])
    }

    @Test func `health weights a mapped token through its identity mapping`() async throws {
        let store = try Store()

        let health = try await Self.readModel(store).overview.health

        #expect(health.weights.map(\.symbol) == ["ETH", "DEGEN"])
        #expect(health.weights.map(\.usdValue) == [6000 * Self.rate, 100 * Self.rate])
        #expect(health.metrics.assetCount == 2)
    }

    @Test func `an ignore override from the store excludes the token`() async throws {
        let store = try Store(ignoring: ["DEGEN"])

        let headline = try await Self.readModel(store).valued.headline

        #expect(headline.total == 6000 * Self.rate)
    }

    @Test(arguments: [false, true])
    func `the overview price inputs read the usd book`(includingLiveChanges: Bool) throws {
        let store = try Store()
        let historical = HistoricalMarketPrices(closesUSD: [:], changes24h: ["bitcoin": Fixture.decimal("0.02")])

        let prices = ValuationPriceInputs.live(store.appState, historical: historical, includingLiveChanges: includingLiveChanges)

        #expect(prices.livePricesUSD == store.appState.livePricesUSD)
        #expect(prices.liveChanges24h == (includingLiveChanges ? store.appState.priceChanges24h : [:]))
        #expect(prices.historical == historical)
    }

    // MARK: - The read model over a store

    /// The projection the projector builds from the store's rows, on its own executor and context as
    /// in production.
    static func project(_ store: Store) async throws -> PortfolioProjection {
        let projector = await PortfolioProjectorClient.makeProjector(modelContainer: store.container)
        return try await projector.build(PortfolioProjectionRequest(isHistoricalBackfillEnabled: false, now: .now))
    }

    /// `projection` valued with the app state's books, rate and currency.
    static func value(
        _ projection: PortfolioProjection,
        in store: Store,
        settings: DashboardSettings = .defaults) -> PortfolioRevaluation {
        PortfolioValuator.compute(PortfolioValuationRequest(
            projection: projection,
            prices: PortfolioPriceInputs(
                livePricesUSD: store.appState.livePricesUSD,
                liveChanges24h: store.appState.priceChanges24h,
                usdToDisplayRate: store.appState.currentUSDToDisplayRate,
                currency: store.appState.selectedCurrency),
            settings: settings))
    }

    /// What the read model values from the store: the projection of its rows, valued.
    static func readModel(_ store: Store, settings: DashboardSettings = .defaults) async throws -> PortfolioRevaluation {
        try await value(project(store), in: store, settings: settings)
    }

    @MainActor
    struct Store {
        let container: ModelContainer
        let positions: [Position]
        let tokens: [PositionToken]
        let mappings: [TokenIdentityMapping]
        let appState: AppState

        /// `ignoring` adds an ignore override row for each listed symbol.
        init(ignoring ignoredSymbols: Set<String> = []) throws {
            self.container = try ModelContainerFactory().makeInMemory()
            let context = container.mainContext
            let syncedAt = Fixture.noon(0)

            let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
            let degen = Asset(
                symbol: "DEGEN",
                name: "Degen",
                upsertChain: .degen,
                upsertContract: OverviewModelWiringTests.degenContract,
                category: .meme)
            let btc = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major)

            let active = Account(name: "Active Wallet", kind: .wallet, dataSource: .zerion)
            let inactive = Account(name: "Old Wallet", kind: .wallet, dataSource: .zerion, isActive: false)
            let wallet = Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 5895,
                tokens: [
                    PositionToken(role: .balance, amount: 2, usdValue: 5800, asset: eth),
                    PositionToken(role: .balance, amount: 10000, usdValue: 95, asset: degen)
                ],
                account: active,
                syncedAt: syncedAt)
            let oldWallet = Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 60000,
                tokens: [PositionToken(role: .balance, amount: 1, usdValue: 60000, asset: btc)],
                account: inactive,
                syncedAt: syncedAt)
            active.positions = [wallet]
            inactive.positions = [oldWallet]

            for model in [eth, degen, btc] {
                context.insert(model)
            }
            context.insert(active)
            context.insert(inactive)
            context.insert(TokenIdentityMapping(
                chain: .degen,
                contractAddress: OverviewModelWiringTests.degenContract,
                coinGeckoId: "degen-base"))
            for asset in [eth, degen, btc] where ignoredSymbols.contains(asset.symbol) {
                context.insert(TokenPricingOverride(assetId: asset.id, isIgnored: true))
            }
            try context.save()

            self.positions = try context.fetch(FetchDescriptor<Position>())
            self.tokens = try context.fetch(FetchDescriptor<PositionToken>())
            self.mappings = try context.fetch(FetchDescriptor<TokenIdentityMapping>())

            self.appState = AppState()
            appState.livePricesUSD = ["ethereum": 3000, "degen-base": Fixture.decimal("0.01"), "bitcoin": 60000]
            appState.priceChanges24h = ["ethereum": Fixture.decimal("0.25")]
            appState.currentUSDToDisplayRate = OverviewModelWiringTests.rate
        }

        /// Adds rows after setup; the next projector build reads them.
        func insert(_ models: [any PersistentModel]) throws {
            for model in models {
                container.mainContext.insert(model)
            }
            try container.mainContext.save()
        }

        /// The seeded categories, with the BTC and ETH categories renamed "Majors" and "L1s", and, by
        /// default, a user rule that files DEGEN under Stablecoins.
        func seedCategories(degenIsStable: Bool = true) throws {
            let context = container.mainContext
            try PortfolioCategorySeeder.seedIfNeeded(in: context)
            let categories = try context.fetch(FetchDescriptor<PortfolioCategory>())
            let names = [PortfolioCategoryDefaults.btcCategoryID: "Majors", PortfolioCategoryDefaults.ethCategoryID: "L1s"]
            for category in categories {
                category.name = names[category.id] ?? category.name
            }
            try context.save()
            guard degenIsStable else { return }
            let stablecoins = categories.first { $0.id == PortfolioCategoryDefaults.stablecoinsCategoryID }
            try insert([CategorySymbolRule(normalizedSymbol: "DEGEN", category: stablecoins)])
        }

        /// A $0.50 holding in the active wallet, below the default $1 dust threshold.
        func addDust() throws {
            let wallet = try #require(positions.first { $0.account?.isActive == true })
            let dust = Asset(symbol: "DUST", name: "Dust", category: .meme)
            let usdValue = PortfolioValuationFixture.decimal("0.5")
            try insert([dust, PositionToken(role: .balance, amount: 1, usdValue: usdValue, asset: dust, position: wallet)])
        }
    }
}
