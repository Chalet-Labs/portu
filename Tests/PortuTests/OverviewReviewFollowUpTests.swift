import Foundation
@testable import Portu
import PortuCore
import Testing

struct OverviewReviewFollowUpTests {
    private typealias Fixture = PortfolioValuationFixture

    @Test func `tab rows use a manual price override`() throws {
        let assetId = UUID()
        let context = Fixture.context(
            tokens: [token(assetId: assetId, symbol: "LOCAL", category: .stablecoin, coinGeckoId: "stale-local", amount: 4, usdValue: 0)],
            overrides: [TokenPricingOverrideSnapshot(assetId: assetId, manualPriceUSD: 2.5)],
            livePricesUSD: ["stale-local": 100],
            liveChanges24h: ["stale-local": Fixture.decimal("0.1")])

        let row = try #require(tab(.idleStables, context).groups.first?.tokens.first)

        #expect(row.price == 2.5)
        #expect(row.value == 10)
        #expect(row.change24h == 0)
    }

    /// The exact formula (V4): 10 × 0.25 / 1.25 = 2.
    @Test func `tab rows use a coin gecko override`() throws {
        let assetId = UUID()
        let context = Fixture.context(
            tokens: [token(assetId: assetId, symbol: "MAP", category: .stablecoin, coinGeckoId: "old-map", amount: 2, usdValue: 1)],
            overrides: [TokenPricingOverrideSnapshot(assetId: assetId, coinGeckoIdOverride: " new-map ")],
            livePricesUSD: ["old-map": 100, "new-map": 5],
            liveChanges24h: ["old-map": Fixture.decimal("0.5"), "new-map": Fixture.decimal("0.25")])

        let row = try #require(tab(.idleStables, context).groups.first?.tokens.first)

        #expect(row.price == 5)
        #expect(row.value == 10)
        #expect(row.change24h == 2)
    }

    /// A3: the cards are not display-filtered, so the 0.25 dust holding counts, and an ignored token
    /// never does.
    @Test func `cards respect overrides and keep dust`() {
        let ignoredStable = token(symbol: "USDT", category: .stablecoin, coinGeckoId: "tether", amount: 1000, usdValue: 1000)
        let manualMajor = token(symbol: "ETH", category: .major, amount: 2, usdValue: 0)
        let staked = token(symbol: "STAKE", category: .defi, coinGeckoId: "old-stake", amount: 3, usdValue: 0)
        let context = ValuationContext(
            inputs: [
                Fixture.input(601, .wallet, token(symbol: "USDC", category: .stablecoin, coinGeckoId: "usd-coin", amount: 100, usdValue: 100)),
                Fixture.input(602, .wallet, ignoredStable),
                Fixture.input(603, .wallet, manualMajor),
                Fixture.input(604, .wallet, token(symbol: "DUST", category: .defi, coinGeckoId: "dust", amount: 1, usdValue: 0.25)),
                Fixture.input(605, .lido, staked)
            ],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignoredStable.assetId, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: manualMajor.assetId, manualPriceUSD: 2000),
                TokenPricingOverrideSnapshot(assetId: staked.assetId, coinGeckoIdOverride: "new-stake")
            ],
            mappings: [],
            settings: .defaults,
            usdToDisplayRate: 1,
            prices: ValuationPriceInputs(livePricesUSD: ["usd-coin": 1, "tether": 1, "dust": 0.25, "old-stake": 100, "new-stake": 5]))

        let cards = OverviewSummaryCardsFeature.cards(context, categories: PortfolioCategoryDefaults.categorySnapshots)

        #expect(cards.map(\.title) == ["Idle", "Deployed", "Debt"])
        #expect(cards[0].rows.map(\.label) == ["Stablecoins & Fiat", "BTC / ETH / SOL", "Tokens & Memecoins"])
        #expect(cards[0].rows.map(\.value) == [100, 4000, 0.25])
        #expect(cards[1].rows.map(\.label) == ["Lending", "Staked", "Yield", "Other"])
        #expect(cards[1].rows.map(\.value) == [0, 15, 0, 0])
        #expect(cards[2].rows.map(\.value) == [0])
    }

    @Test func `cards value an implausible onchain price at zero`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xBadPrice")
        let context = Fixture.context(
            tokens: [token(symbol: "BAD", category: .defi, amount: 1_000_000, usdValue: 10, onchainIdentity: identity)],
            livePricesUSD: [identity.historicalPriceID: 1_000_000])

        let cards = OverviewSummaryCardsFeature.cards(context, categories: PortfolioCategoryDefaults.categorySnapshots)

        #expect(cards[0].rows.map(\.value) == [0, 0, 0])
    }

    /// The threshold hides rows from the dashboard lists only (A3), so a dust manual token still
    /// counts, converted once.
    @Test(arguments: [Decimal(10), 100])
    func `cards count a near dust manual token whatever the threshold`(threshold: Decimal) {
        let assetId = UUID()
        let context = Fixture.context(
            tokens: [token(assetId: assetId, symbol: "NEAR", category: .major, amount: 1, usdValue: 0)],
            overrides: [TokenPricingOverrideSnapshot(assetId: assetId, manualPriceUSD: Fixture.decimal("10.50"))],
            settings: TokenDashboardSettings(minimumDashboardValue: threshold, hideUnpriced: true, hideDust: true),
            rate: Fixture.decimal("0.5"))

        let cards = OverviewSummaryCardsFeature.cards(context, categories: PortfolioCategoryDefaults.categorySnapshots)

        #expect(cards[0].rows.map(\.value) == [0, 0, Fixture.decimal("5.25")])
    }

    @Test func `category slices use stable ids when equal value category names collide`() throws {
        let laterID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let earlierID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let laterCategory = PortfolioCategorySnapshot(
            id: laterID,
            name: "Duplicate",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let earlierCategory = PortfolioCategorySnapshot(
            id: earlierID,
            name: "Duplicate",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let tokens = [laterCategory, earlierCategory].map { category in
            TokenEntry(
                assetId: UUID(),
                symbol: category.id == laterID ? "LATER" : "EARLIER",
                name: category.id == laterID ? "LATER" : "EARLIER",
                category: .other,
                portfolioCategory: category,
                coinGeckoId: category.id == laterID ? "later" : "earlier",
                role: .balance,
                amount: 1,
                usdValue: 10)
        }

        let slices = OverviewFeature.topAssets(
            .category,
            context: Fixture.context(tokens: tokens, livePricesUSD: ["later": 10, "earlier": 10])).slices

        #expect(slices.map(\.id) == [earlierID.uuidString, laterID.uuidString])
    }

    private func tab(_ tab: OverviewPositionTab, _ context: ValuationContext) -> OverviewPositionTabData {
        OverviewPositionProjection.tab(tab, context: context, positions: Fixture.positions)
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        category: AssetCategory = .major,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: category,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue)
    }
}
