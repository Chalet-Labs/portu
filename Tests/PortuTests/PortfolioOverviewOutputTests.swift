import Foundation
@testable import Portu
import PortuCore
import Testing

/// The Overview panels' outputs from one revaluation against today's seams over the contexts the
/// views built in their bodies (#124 PR 1, spec O1–O2). The holdings and the active tokens differ
/// in content, order and categories, so a panel fed the wrong list fails.
struct PortfolioOverviewOutputTests {
    private typealias Fixture = PortfolioValuationFixture

    /// The store's rules put DEGEN under Stablecoins; the default rules don't.
    private static let stablecoins = PortfolioCategoryResolver.defaults.categories.first { $0.semanticRole == .stablecoin }!
    private static let storeCategorized = Fixture.inputs.map { input in
        input.token.symbol == "DEGEN" ? recategorized(input, as: stablecoins) : input
    }

    /// Today's lists: the cards and tabs walked the positions, the rest the token table.
    private static let holdingsToday = Array(storeCategorized.dropFirst())
    private static let tokensToday = Array(storeCategorized.reversed())
    /// What polling ranked today: the token table with the default rules.
    private static let pollingToday = Array(Fixture.inputs.reversed())

    private static let candidates = [
        OverviewAssetCandidate(
            id: Fixture.uuid(9001),
            symbol: "BTC",
            name: "Bitcoin",
            category: .major,
            coinGeckoId: "bitcoin",
            logoURL: nil),
        OverviewAssetCandidate(
            id: Fixture.uuid(9002),
            symbol: "DOGE",
            name: "Dogecoin",
            category: .meme,
            coinGeckoId: "dogecoin",
            logoURL: "doge.png")
    ]

    private static var projection: PortfolioProjection {
        var projection = PortfolioProjection.empty
        projection.holdings = PortfolioValuation.prepare(holdingsToday, overrides: Fixture.overrides, mappings: Fixture.mappings)
        projection.activeTokens = PortfolioValuation.prepare(tokensToday, overrides: Fixture.overrides, mappings: Fixture.mappings)
        projection.positionMeta = Fixture.positions
        projection.overrides = Fixture.overrides
        projection.mappings = Fixture.mappings
        projection.watchlistCandidates = candidates
        projection.historical = Fixture.historical
        return projection
    }

    private static let settings = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: true, watchlistIDs: Fixture.watchlistIDs)

    private static func revaluation(
        rate: Decimal = 1,
        currency: FiatCurrency = .usd,
        liveChanges24h: [String: Decimal] = Fixture.liveChanges24h) -> PortfolioRevaluation {
        PortfolioValuator.compute(PortfolioValuationRequest(
            projection: projection,
            prices: PortfolioPriceInputs(
                livePricesUSD: Fixture.livePricesUSD,
                liveChanges24h: liveChanges24h,
                usdToDisplayRate: rate,
                currency: currency),
            settings: settings))
    }

    @Test(arguments: [(Decimal(1), FiatCurrency.usd), (Fixture.decimal("0.9"), FiatCurrency.eur)])
    func `every panel equals today's seam over today's context`(rate: Decimal, currency: FiatCurrency) {
        let output = Self.revaluation(rate: rate, currency: currency)

        let holdings = Fixture.context(rate: rate, inputs: Self.holdingsToday)
        let holdingsWithoutFractions = Fixture.context(rate: rate, inputs: Self.holdingsToday, liveChanges24h: [:])
        let tokensWithoutFractions = Fixture.context(rate: rate, inputs: Self.tokensToday, liveChanges24h: [:])
        // What the watchlist read on master: the token table under the default rules, with the live fractions.
        let watchlistToday = Fixture.context(rate: rate, inputs: Self.pollingToday)
        let overview = output.overview
        #expect(output.valued.headline == OverviewFeature.headline(holdings))
        #expect(output.valued.pricePollingIDs == OverviewFeature.pricePollingIDs(
            Fixture.context(rate: rate, inputs: Self.pollingToday, liveChanges24h: [:]),
            watchlistIDs: Fixture.watchlistIDs))
        #expect(overview.currencyCode == currency.displayCode)
        #expect(overview.summaryCards == OverviewSummaryCardsFeature.cards(holdingsWithoutFractions, categories: Self.projection.categories))
        for tab in OverviewPositionTab.allCases {
            #expect(overview.positionTabs[tab] == OverviewPositionProjection.tab(tab, context: holdings, positions: Fixture.positions), "\(tab)")
        }
        for mode in [TopAssetMode.assets, .category] {
            #expect(overview.topAssets[mode] == OverviewFeature.topAssets(mode, context: tokensWithoutFractions), "\(mode)")
        }
        #expect(overview.health == PortfolioHealthFeature.health(tokensWithoutFractions))
        #expect(overview.watchlistRows == OverviewFeature.watchlistRows(watchlistToday, assets: Self.candidates, watchlistIDs: Fixture.watchlistIDs))
    }

    /// Guards the oracle above: each list really differs where a panel could be fed the wrong one.
    @Test func `the fixture's lists differ where a wiring mistake would show`() {
        let holdings = Fixture.context(inputs: Self.holdingsToday, liveChanges24h: [:])
        let tokens = Fixture.context(inputs: Self.tokensToday, liveChanges24h: [:])
        let holdingsLive = Fixture.context(inputs: Self.holdingsToday)
        let tokensLive = Fixture.context(inputs: Self.tokensToday)
        let watchlistToday = Fixture.context(inputs: Self.pollingToday)

        #expect(OverviewSummaryCardsFeature.cards(holdings, categories: []) != OverviewSummaryCardsFeature.cards(tokens, categories: []))
        #expect(PortfolioHealthFeature.health(holdings) != PortfolioHealthFeature.health(tokens))
        #expect(
            OverviewFeature.topAssets(.assets, context: holdings) != OverviewFeature.topAssets(.assets, context: tokens),
            "the holdings leave out a token the table has")
        #expect(
            OverviewFeature.topAssets(.category, context: tokens)
                != OverviewFeature.topAssets(.category, context: Fixture.context(inputs: Self.pollingToday, liveChanges24h: [:])),
            "the store's DEGEN rule moves a category slice")
        #expect(
            OverviewPositionTab.allCases.contains { tab in
                OverviewPositionProjection.tab(tab, context: holdingsLive, positions: Fixture.positions)
                    != OverviewPositionProjection.tab(tab, context: tokensLive, positions: Fixture.positions)
            },
            "a tab fed the token table shows other groups")
        #expect(
            OverviewFeature.watchlistRows(holdingsLive, assets: Self.candidates, watchlistIDs: Fixture.watchlistIDs)
                != OverviewFeature.watchlistRows(watchlistToday, assets: Self.candidates, watchlistIDs: Fixture.watchlistIDs),
            "a watchlist fed the holdings misses a row the token table has")
        let summary = OverviewSummaryCardsFeature.cards(holdings, categories: [])
        #expect(
            summary != OverviewSummaryCardsFeature.cards(
                Fixture.context(inputs: Array(Fixture.inputs.dropFirst()), liveChanges24h: [:]),
                categories: []),
            "the store's DEGEN rule moves an idle bucket")
    }

    /// The cards, the donut and health show no 24h figure, so they are valued with the live
    /// fractions and still don't move when only the fractions do.
    @Test func `a change to the live fractions alone leaves the cards, donut and health equal`() {
        let before = Self.revaluation().overview
        var fractions = Fixture.liveChanges24h
        for key in fractions.keys {
            fractions[key] = -(fractions[key] ?? 0)
        }

        let after = Self.revaluation(liveChanges24h: fractions).overview

        #expect(after.summaryCards == before.summaryCards)
        #expect(after.topAssets == before.topAssets)
        #expect(after.health == before.health)
        #expect(after.positionTabs != before.positionTabs, "the tabs show a 24h change")
        #expect(after.watchlistRows != before.watchlistRows, "the watchlist shows a 24h change")
    }

    /// One valuation per list feeds every seam over it; each seam gives what it gave valuing alone.
    @Test func `a memoized context gives every seam today's output`() {
        let plain = Fixture.context()
        let memoized = plain.memoized()

        #expect(OverviewFeature.headline(memoized) == OverviewFeature.headline(plain))
        #expect(OverviewSummaryCardsFeature.cards(memoized, categories: []) == OverviewSummaryCardsFeature.cards(plain, categories: []))
        #expect(OverviewFeature.topAssets(.assets, context: memoized) == OverviewFeature.topAssets(.assets, context: plain))
        #expect(PortfolioHealthFeature.health(memoized) == PortfolioHealthFeature.health(plain))
        #expect(OverviewFeature.watchlistRows(memoized, assets: Self.candidates, watchlistIDs: Fixture.watchlistIDs)
            == OverviewFeature.watchlistRows(plain, assets: Self.candidates, watchlistIDs: Fixture.watchlistIDs))
        #expect(OverviewFeature.pricePollingIDs(memoized, watchlistIDs: []) == OverviewFeature.pricePollingIDs(plain, watchlistIDs: []))
        for tab in OverviewPositionTab.allCases {
            #expect(
                OverviewPositionProjection.tab(tab, context: memoized, positions: Fixture.positions)
                    == OverviewPositionProjection.tab(tab, context: plain, positions: Fixture.positions),
                "\(tab)")
        }
    }

    private static func recategorized(_ input: ValuationInput, as category: PortfolioCategorySnapshot) -> ValuationInput {
        let token = input.token
        return ValuationInput(
            tokenId: input.tokenId,
            token: TokenEntry(
                assetId: token.assetId,
                symbol: token.symbol,
                name: token.name,
                category: token.category,
                portfolioCategory: category,
                coinGeckoId: token.coinGeckoId,
                onchainIdentity: token.onchainIdentity,
                role: token.role,
                amount: token.amount,
                usdValue: token.usdValue,
                logoURL: token.logoURL,
                syncedAt: token.syncedAt),
            position: input.position)
    }
}
