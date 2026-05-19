import Foundation
@testable import Portu
import PortuCore
import Testing

struct OverviewReviewFollowUpTests {
    @Test func `position pricing uses manual price overrides`() {
        let assetId = UUID()
        let local = token(assetId: assetId, symbol: "LOCAL", coinGeckoId: "stale-local", amount: 4, usdValue: 0)
        let override = TokenPricingOverrideSnapshot(assetId: assetId, manualPriceUSD: 2.5)

        #expect(OverviewPositionPricing.price(
            token: local,
            prices: ["stale-local": 100],
            override: override) == 2.5)
        #expect(OverviewPositionPricing.tokenValue(
            token: local,
            prices: ["stale-local": 100],
            override: override) == 10)
        #expect(OverviewPositionPricing.change24h(
            token: local,
            prices: ["stale-local": 100],
            changes24h: ["stale-local": 0.10],
            override: override) == 0)
    }

    @Test func `position pricing uses coin gecko overrides`() {
        let assetId = UUID()
        let mapped = token(assetId: assetId, symbol: "MAP", coinGeckoId: "old-map", amount: 2, usdValue: 1)
        let override = TokenPricingOverrideSnapshot(assetId: assetId, coinGeckoIdOverride: " new-map ")

        #expect(OverviewPositionPricing.price(
            token: mapped,
            prices: ["old-map": 100, "new-map": 5],
            override: override) == 5)
        #expect(OverviewPositionPricing.tokenValue(
            token: mapped,
            prices: ["old-map": 100, "new-map": 5],
            override: override) == 10)
        #expect(OverviewPositionPricing.change24h(
            token: mapped,
            prices: ["old-map": 100, "new-map": 5],
            changes24h: ["old-map": 0.50, "new-map": 0.10],
            override: override) == 1)
    }

    @Test func `summary breakdowns respect dashboard visibility and overrides`() {
        let ignoredStableId = UUID()
        let manualMajorId = UUID()
        let visibleStable = summaryToken(
            token(symbol: "USDC", category: .stablecoin, coinGeckoId: "usd-coin", amount: 100, usdValue: 100),
            positionType: .idle)
        let ignoredStable = summaryToken(
            token(assetId: ignoredStableId, symbol: "USDT", category: .stablecoin, coinGeckoId: "tether", amount: 1000, usdValue: 1000),
            positionType: .idle)
        let manualMajor = summaryToken(
            token(assetId: manualMajorId, symbol: "ETH", category: .major, amount: 2, usdValue: 0),
            positionType: .idle)
        let dustToken = summaryToken(
            token(symbol: "DUST", category: .defi, coinGeckoId: "dust", amount: 1, usdValue: 0.25),
            positionType: .idle)
        let deployedMapped = summaryToken(
            token(symbol: "STAKE", category: .defi, coinGeckoId: "old-stake", amount: 3, usdValue: 0),
            positionType: .staking)

        let overrides = [
            TokenPricingOverrideSnapshot(assetId: ignoredStableId, isIgnored: true),
            TokenPricingOverrideSnapshot(assetId: manualMajorId, manualPriceUSD: 2000),
            TokenPricingOverrideSnapshot(assetId: deployedMapped.token.assetId, coinGeckoIdOverride: "new-stake")
        ]

        let idle = OverviewSummaryCardsFeature.idleBreakdown(
            tokens: [visibleStable, ignoredStable, manualMajor, dustToken],
            prices: ["usd-coin": 1, "tether": 1, "dust": 0.25],
            overrides: overrides,
            categories: PortfolioCategoryDefaults.categorySnapshots)
        let deployed = OverviewSummaryCardsFeature.deployedBreakdown(
            tokens: [deployedMapped],
            prices: ["old-stake": 100, "new-stake": 5],
            overrides: overrides)

        #expect(idle.map(\.0) == ["Stablecoins & Fiat", "BTC / ETH / SOL", "Tokens & Memecoins"])
        #expect(idle.map(\.1) == [100, 4000, 0])
        #expect(deployed.map(\.0) == ["Lending", "Staked", "Yield"])
        #expect(deployed.map(\.1) == [0, 15, 0])
    }

    @Test func `summary breakdowns exclude implausible onchain provider prices`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xBadPrice")
        let bad = summaryToken(
            token(
                symbol: "BAD",
                category: .defi,
                amount: 1_000_000,
                usdValue: 10,
                onchainIdentity: identity),
            positionType: .idle)

        let idle = OverviewSummaryCardsFeature.idleBreakdown(
            tokens: [bad],
            prices: [identity.historicalPriceID: 1_000_000],
            overrides: [],
            categories: PortfolioCategoryDefaults.categorySnapshots)

        #expect(idle.map(\.1) == [0, 0, 0])
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
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "LATER",
                name: "LATER",
                category: .other,
                portfolioCategory: laterCategory,
                coinGeckoId: "later",
                role: .balance,
                amount: 1,
                usdValue: 10),
            TokenEntry(
                assetId: UUID(),
                symbol: "EARLIER",
                name: "EARLIER",
                category: .other,
                portfolioCategory: earlierCategory,
                coinGeckoId: "earlier",
                role: .balance,
                amount: 1,
                usdValue: 10)
        ]

        let slices = OverviewFeature.categorySlices(from: tokens, prices: ["later": 10, "earlier": 10], limit: 2)

        #expect(slices.map(\.id) == [earlierID.uuidString, laterID.uuidString])
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

    private func summaryToken(
        _ token: TokenEntry,
        positionType: PositionType) -> OverviewSummaryToken {
        OverviewSummaryToken(token: token, positionType: positionType)
    }
}
