import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// Each Overview panel's output from the portfolio read model, projected from the in-memory store
/// and valued (#123, #124): the overrides, mappings, live 24h fractions and category rules each panel
/// sees. The store and rate are in `OverviewModelWiringTests`.
extension OverviewModelWiringTests {
    /// ETH's +25% is only in the live fractions, so only a panel that reads them shows it.
    @Test func `the headline, tabs and watchlist read the live 24h fractions`() async throws {
        let model = try await Self.readModel(Store())
        let keyChanges = try #require(model.overview.positionTabs[.keyChanges]).groups.flatMap(\.tokens)

        #expect(model.valued.headline.total == 6100 * Self.rate)
        #expect(model.valued.headline.change24h == 1200 * Self.rate)
        #expect(keyChanges.map(\.symbol) == ["ETH"])
        #expect(keyChanges.map(\.change24h) == [1200 * Self.rate])
        #expect(model.overview.watchlistRows.map(\.symbol) == ["ETH", "DEGEN"])
        #expect(model.overview.watchlistRows.map(\.change24h) == [PortfolioValuationFixture.decimal("0.25"), nil])
    }

    @Test func `every panel values a mapped token through its identity mapping`() async throws {
        let model = try await Self.readModel(Store())
        let assetSlices = try #require(model.overview.topAssets[.assets])

        #expect(try model.idle() == [0, 6000 * Self.rate, 100 * Self.rate])
        #expect(model.overview.watchlistRows.map(\.price) == [3000 * Self.rate, PortfolioValuationFixture.decimal("0.01") * Self.rate])
        #expect(assetSlices.slices.map(\.label) == ["ETH", "DEGEN"])
        #expect(assetSlices.slices.map(\.value) == [6000 * Self.rate, 100 * Self.rate])
        #expect(model.overview.health.weights.map(\.usdValue) == [6000 * Self.rate, 100 * Self.rate])
        #expect(model.overview.health.metrics.assetCount == 2)
        #expect(Set(model.valued.pricePollingIDs) == ["ethereum", "degen-base"])
    }

    /// The store's DEGEN → Stablecoins rule moves DEGEN out of the Idle card's tokens bucket, into the
    /// Idle Stables tab, a category-mode donut slice and Health's stablecoin share.
    @Test func `the cards, tabs, donut and health apply the store's category rules`() async throws {
        let plain = try await Self.readModel(Store())
        let ruled = try Store()
        try ruled.seedCategories()
        let model = try await Self.readModel(ruled)
        let stablecoins = PortfolioCategoryDefaults.stablecoinsCategoryID.uuidString
        let idleStables = try #require(model.overview.positionTabs[.idleStables])
        let categorySlices = try #require(model.overview.topAssets[.category]).slices
        let plainIdleStables = try #require(plain.overview.positionTabs[.idleStables])
        let plainCategorySlices = try #require(plain.overview.topAssets[.category]).slices

        #expect(try model.idle() == [100 * Self.rate, 6000 * Self.rate, 0])
        #expect(idleStables.groups.flatMap(\.tokens).map(\.value) == [100 * Self.rate])
        #expect(categorySlices.first { $0.id == stablecoins }?.value == 100 * Self.rate)
        #expect(model.overview.health.metrics.stablecoinRatio > 0)
        #expect(plainIdleStables.groups.isEmpty)
        #expect(!plainCategorySlices.contains { $0.id == stablecoins })
        #expect(plain.overview.health.metrics.stablecoinRatio == 0)
    }

    /// A user who renamed the two major categories sees their names on the Idle card's majors row.
    @Test func `the cards label the majors row with the store's category names`() async throws {
        let store = try Store()
        try store.seedCategories(degenIsStable: false)

        let model = try await Self.readModel(store)
        let idle = try #require(model.overview.summaryCards.first { $0.title == "Idle" })

        #expect(idle.rows.map(\.label) == ["Stablecoins & Fiat", "Majors / L1s / SOL", "Tokens & Memecoins"])
        #expect(idle.rows.map(\.value) == [0, 6000 * Self.rate, 100 * Self.rate])
    }

    /// A Solana asset the store knows only through an override row that sets its CoinGecko ID,
    /// watched under that ID and not held.
    @Test(arguments: [false, true])
    func `the watchlist finds a watched asset through its coin gecko id override`(ignored: Bool) async throws {
        let store = try Store()
        let solana = Asset(symbol: "SOL", name: "Solana", coinGeckoId: "solana-old", category: .major)
        try store.insert([solana, TokenPricingOverride(assetId: solana.id, coinGeckoIdOverride: "solana", isIgnored: ignored)])
        let watching = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: false, watchlistIDs: ["solana"])

        let projection = try await Self.project(store)
        let rows = Self.value(projection, in: store, settings: watching).overview.watchlistRows.filter(\.isWatchlisted)
        let suggestions = OverviewFeature.watchlistSuggestions(assets: projection.watchlistCandidates, watchlistIDs: [], query: "Solana")

        #expect(suggestions.map(\.coinGeckoId) == ["solana"])
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
    @Test func `every panel values the store's override rows`() async throws {
        let store = try Store(ignoring: ["DEGEN"])
        try store.seedCategories()

        let model = try await Self.readModel(store)
        let idleStables = try #require(model.overview.positionTabs[.idleStables])
        let assetSlices = try #require(model.overview.topAssets[.assets])

        #expect(model.valued.headline.total == 6000 * Self.rate)
        #expect(try model.idle() == [0, 6000 * Self.rate, 0])
        #expect(idleStables.groups.isEmpty)
        #expect(model.overview.watchlistRows.map(\.symbol) == ["ETH"])
        #expect(assetSlices.slices.map(\.label) == ["ETH"])
        #expect(model.overview.health.weights.map(\.symbol) == ["ETH"])
        #expect(model.overview.health.metrics.assetCount == 1)
        #expect(model.valued.pricePollingIDs == ["ethereum"])
    }
}

extension PortfolioRevaluation {
    /// The Idle card's row values.
    func idle() throws -> [Decimal] {
        try #require(overview.summaryCards.first { $0.title == "Idle" }).rows.map(\.value)
    }
}
