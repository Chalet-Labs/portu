import Foundation
import Observation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// Each Overview screen's method on `ValuationSources`, rendered over the in-memory store, and the
/// headline and polling IDs the portfolio read model values from the same store (#123).
/// The method fixes which books the screen reads, so these pin the overrides, mappings, live 24h
/// fractions and category rules each screen sees. The store and rate are in `OverviewModelWiringTests`.
extension OverviewModelWiringTests {
    /// Every screen at once, from one body pass.
    struct Screens {
        let settings: TokenDashboardSettings
        let cards: [OverviewSummaryCard]
        let keyChanges: OverviewPositionTabData
        let idleStables: OverviewPositionTabData
        let watchlist: [OverviewPriceRowData]
        let assetSlices: OverviewTopAssets
        let categorySlices: OverviewTopAssets
        let health: PortfolioHealthData

        func idle() throws -> [Decimal] {
            try #require(cards.first { $0.title == "Idle" }).rows.map(\.value)
        }
    }

    /// A user rule that files DEGEN under Stablecoins.
    static let degenIsStable = PortfolioCategoryResolver(
        categories: PortfolioCategoryDefaults.categorySnapshots,
        rules: PortfolioCategoryDefaults.symbolRuleSnapshots + [
            CategorySymbolRuleSnapshot(id: UUID(), symbol: "DEGEN", categoryId: PortfolioCategoryDefaults.stablecoinsCategoryID)
        ])

    static func screens(_ store: Store, categoryResolver: PortfolioCategoryResolver = .defaults) -> Screens? {
        probe(store) { sources, positions, tokens, assets in
            Screens(
                settings: sources.settings,
                cards: sources.summaryCards(positions, categoryResolver: categoryResolver),
                keyChanges: sources.positionTab(.keyChanges, positions: positions, categoryResolver: categoryResolver),
                idleStables: sources.positionTab(.idleStables, positions: positions, categoryResolver: categoryResolver),
                watchlist: sources.watchlistRows(tokens, assets: assets, watchlistIDs: []),
                assetSlices: sources.topAssets(.assets, tokens: tokens, categoryResolver: categoryResolver),
                categorySlices: sources.topAssets(.category, tokens: tokens, categoryResolver: categoryResolver),
                health: sources.health(tokens, categoryResolver: categoryResolver))
        }
    }

    /// What the read model values from the store: the projection the projector builds from these
    /// rows, valued with the app state's books and rate under the default settings.
    static func readModel(_ store: Store) throws -> PortfolioValuedOutput {
        let context = store.container.mainContext
        let projection = try PortfolioProjection(
            positions: context.fetch(FetchDescriptor<Position>()),
            tokens: context.fetch(FetchDescriptor<PositionToken>()),
            assets: context.fetch(FetchDescriptor<Asset>()),
            accounts: context.fetch(FetchDescriptor<Account>()),
            overrides: context.fetch(FetchDescriptor<TokenPricingOverride>()),
            mappings: context.fetch(FetchDescriptor<TokenIdentityMapping>()),
            categoryResolver: .defaults,
            historicalRows: [],
            request: PortfolioProjectionRequest(isHistoricalBackfillEnabled: false, now: .now))
        return PortfolioValuator.compute(PortfolioValuationRequest(
            projection: projection,
            prices: PortfolioPriceInputs(
                livePricesUSD: store.appState.livePricesUSD,
                liveChanges24h: store.appState.priceChanges24h,
                usdToDisplayRate: store.appState.currentUSDToDisplayRate,
                currency: store.appState.selectedCurrency),
            settings: .defaults))
    }

    @Test func `the probe reads the default dashboard settings`() throws {
        let screens = try #require(Self.screens(Store()))

        #expect(screens.settings == .defaults)
    }

    /// ETH's +25% is only in the live fractions, so only a screen that reads them shows it.
    @Test func `the headline, tabs and watchlist read the live 24h fractions`() throws {
        let store = try Store()
        let screens = try #require(Self.screens(store))
        let headline = try Self.readModel(store).headline
        let keyChanges = screens.keyChanges.groups.flatMap(\.tokens)

        #expect(headline.total == 6100 * Self.rate)
        #expect(headline.change24h == 1200 * Self.rate)
        #expect(keyChanges.map(\.symbol) == ["ETH"])
        #expect(keyChanges.map(\.change24h) == [1200 * Self.rate])
        #expect(screens.watchlist.map(\.symbol) == ["ETH", "DEGEN"])
        #expect(screens.watchlist.map(\.change24h) == [PortfolioValuationFixture.decimal("0.25"), nil])
    }

    @Test func `every screen values a mapped token through its identity mapping`() throws {
        let store = try Store()
        let screens = try #require(Self.screens(store))

        #expect(try screens.idle() == [0, 6000 * Self.rate, 100 * Self.rate])
        #expect(screens.watchlist.map(\.price) == [3000 * Self.rate, PortfolioValuationFixture.decimal("0.01") * Self.rate])
        #expect(screens.assetSlices.slices.map(\.label) == ["ETH", "DEGEN"])
        #expect(screens.assetSlices.slices.map(\.value) == [6000 * Self.rate, 100 * Self.rate])
        #expect(screens.health.weights.map(\.usdValue) == [6000 * Self.rate, 100 * Self.rate])
        #expect(screens.health.metrics.assetCount == 2)
        #expect(try Set(Self.readModel(store).pricePollingIDs) == ["ethereum", "degen-base"])
    }

    @Test func `the cards, tabs, donut and health apply the view's category rules`() throws {
        let plain = try #require(Self.screens(Store()))
        let screens = try #require(Self.screens(Store(), categoryResolver: Self.degenIsStable))
        let stablecoins = PortfolioCategoryDefaults.stablecoinsCategoryID.uuidString

        #expect(try screens.idle() == [100 * Self.rate, 6000 * Self.rate, 0])
        #expect(screens.idleStables.groups.flatMap(\.tokens).map(\.value) == [100 * Self.rate])
        #expect(screens.categorySlices.slices.first { $0.id == stablecoins }?.value == 100 * Self.rate)
        #expect(screens.health.metrics.stablecoinRatio > 0)
        #expect(plain.idleStables.groups.isEmpty)
        #expect(!plain.categorySlices.slices.contains { $0.id == stablecoins })
        #expect(plain.health.metrics.stablecoinRatio == 0)
    }

    /// A user who renamed the two major categories sees their names on the Idle card's majors row.
    @Test func `the cards label the majors row with the resolver's category names`() throws {
        let renamed = PortfolioCategoryResolver(
            categories: PortfolioCategoryDefaults.categorySnapshots.map { category in
                let names = [PortfolioCategoryDefaults.btcCategoryID: "Majors", PortfolioCategoryDefaults.ethCategoryID: "L1s"]
                return PortfolioCategorySnapshot(
                    id: category.id,
                    name: names[category.id] ?? category.name,
                    sortOrder: category.sortOrder,
                    semanticRole: category.semanticRole,
                    isSystemRequired: category.isSystemRequired)
            },
            rules: PortfolioCategoryDefaults.symbolRuleSnapshots)

        let screens = try #require(Self.screens(Store(), categoryResolver: renamed))
        let idle = try #require(screens.cards.first { $0.title == "Idle" })

        #expect(idle.rows.map(\.label) == ["Stablecoins & Fiat", "Majors / L1s / SOL", "Tokens & Memecoins"])
        #expect(idle.rows.map(\.value) == [0, 6000 * Self.rate, 100 * Self.rate])
    }

    /// The cards, tabs, donut and Health read their resolver from one `OverviewCategorySource`,
    /// which owns the category and rule queries.
    @Test func `the category source builds its resolver from the store's categories and rules`() throws {
        let store = try Store()
        let empty = try #require(Self.categoryResolver(store))
        try store.seedCategories()

        let resolver = try #require(Self.categoryResolver(store))
        let stablecoins = PortfolioCategoryDefaults.stablecoinsCategoryID

        #expect(empty == .defaults)
        #expect(resolver.resolve(symbol: "DEGEN", legacyCategory: .meme).id == stablecoins)
        #expect(resolver.categories.first { $0.id == PortfolioCategoryDefaults.ethCategoryID }?.name == "L1s")
        #expect(PortfolioCategoryResolver.defaults.resolve(symbol: "DEGEN", legacyCategory: .meme).id != stablecoins)
    }

    /// A Solana asset the store knows only through an override row that sets its CoinGecko ID,
    /// watched under that ID and not held.
    @Test(arguments: [false, true])
    func `the watchlist finds a watched asset through its coin gecko id override`(ignored: Bool) throws {
        let store = try Store()
        let solana = Asset(symbol: "SOL", name: "Solana", coinGeckoId: "solana-old", category: .major)
        try store.insert([solana, TokenPricingOverride(assetId: solana.id, coinGeckoIdOverride: "solana", isIgnored: ignored)])

        let watched = try #require(Self.probe(store) { sources, _, tokens, assets in
            (
                rows: sources.watchlistRows(tokens, assets: assets, watchlistIDs: ["solana"]),
                suggestions: sources.watchlistSuggestions(assets, watchlistIDs: [], query: "Solana"))
        })
        let rows = watched.rows.filter(\.isWatchlisted)

        #expect(watched.suggestions.map(\.coinGeckoId) == ["solana"])
        if ignored {
            #expect(rows.isEmpty)
        } else {
            #expect(rows.map(\.coinGeckoId) == ["solana"])
            #expect(rows.map(\.symbol) == ["SOL"])
            #expect(rows.map(\.name) == ["Solana"])
            #expect(rows.map(\.assetId) == [solana.id])
        }
    }

    /// An ignore override row on DEGEN, which the category rule files under Stablecoins so the
    /// Idle Stables tab would show it.
    @Test func `every screen values the store's override rows`() throws {
        let store = try Store(ignoring: ["DEGEN"])
        let screens = try #require(Self.screens(store, categoryResolver: Self.degenIsStable))
        let readModel = try Self.readModel(store)

        #expect(readModel.headline.total == 6000 * Self.rate)
        #expect(try screens.idle() == [0, 6000 * Self.rate, 0])
        #expect(screens.idleStables.groups.isEmpty)
        #expect(screens.watchlist.map(\.symbol) == ["ETH"])
        #expect(screens.assetSlices.slices.map(\.label) == ["ETH"])
        #expect(screens.health.weights.map(\.symbol) == ["ETH"])
        #expect(screens.health.metrics.assetCount == 1)
        #expect(readModel.pricePollingIDs == ["ethereum"])
    }

    /// The cards, donut and Health show no 24h figure, so a change to the live fractions alone must
    /// not re-render them (the Overview re-render costs seconds in Debug). A real poll writes the
    /// prices too, and every view reads those, so this covers a fraction-only change, not every
    /// tick. The headline and polling are reducer state since #123 and observe no `AppState`.
    @Test func `only the tabs and watchlist observe a fraction only change`() throws {
        let store = try Store()

        let flags = try #require(Self.probe(store) { sources, positions, tokens, assets in
            [
                "cards": Self.observing { _ = sources.summaryCards(positions, categoryResolver: .defaults) },
                "tabs": Self.observing { _ = sources.positionTab(.keyChanges, positions: positions, categoryResolver: .defaults) },
                "watchlist": Self.observing { _ = sources.watchlistRows(tokens, assets: assets, watchlistIDs: []) },
                "donut": Self.observing { _ = sources.topAssets(.assets, tokens: tokens, categoryResolver: .defaults) },
                "health": Self.observing { _ = sources.health(tokens, categoryResolver: .defaults) }
            ]
        })
        store.appState.priceChanges24h["solana"] = PortfolioValuationFixture.decimal("0.1")

        #expect(flags.filter(\.value.changed).keys.sorted() == ["tabs", "watchlist"])
    }

    final class ObservationFlag: @unchecked Sendable {
        var changed = false
    }

    private static func observing(_ read: () -> Void) -> ObservationFlag {
        let flag = ObservationFlag()
        withObservationTracking(read) { flag.changed = true }
        return flag
    }
}
