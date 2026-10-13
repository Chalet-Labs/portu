import Foundation
import PortuCore
import Testing

struct ValuationPriceIDTests {
    private typealias Fixture = ValuationFixtures

    @Test func `coin gecko id plus ethereum identity resolves to the onchain price id`() {
        let identity = Fixture.onchain(.ethereum, "0xABC")
        let token = Fixture.token(coinGeckoId: "usd-coin", onchainIdentity: identity)

        #expect(TokenPricingOverrideFeature.resolvedPriceID(token: token, override: nil) == identity.historicalPriceID)
        #expect(Fixture.valued(token).priceID == identity.historicalPriceID)
    }

    @Test func `onchain price id resolved despite a coin gecko id is plausibility checked`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(coinGeckoId: "usd-coin", onchainIdentity: identity, amount: 100, usdValue: 100)
        let market = Fixture.market(live: ["usd-coin": 1, identity.historicalPriceID: 500])

        let valued = Fixture.valued(token, market: market)

        #expect(valued.source == .unpriced)
        #expect(valued.value == 0)
    }

    @Test func `native sentinel on an eth family chain resolves to the native coin gecko id`() {
        let token = Fixture.token(onchainIdentity: .native(on: .arbitrum))

        #expect(TokenPricingOverrideFeature.resolvedPriceID(token: token, override: nil) == "ethereum")
    }

    @Test func `chain without a coin gecko platform uses the override coin gecko id`() {
        let token = Fixture.token(onchainIdentity: Fixture.onchain(.bitcoin, "bc1-token"))
        let override = TokenPricingOverrideSnapshot(assetId: token.assetId, coinGeckoIdOverride: " Wrapped-BTC ")

        #expect(TokenPricingOverrideFeature.resolvedPriceID(token: token, override: override) == "wrapped-btc")
    }

    @Test func `chain without a coin gecko platform and no coin gecko id keeps the onchain price id`() {
        let identity = Fixture.onchain(.bitcoin, "bc1-token")
        let token = Fixture.token(onchainIdentity: identity)

        #expect(TokenPricingOverrideFeature.resolvedPriceID(token: token, override: nil) == identity.historicalPriceID)
    }

    @Test func `identity mapping supplies the coin gecko id when the asset has none`() {
        let identity = Fixture.onchain(.hyperEVM, "0xfeed")
        let token = Fixture.token(onchainIdentity: identity)
        let mappings = TokenIdentityMappingFeature.mappingsByIdentity([
            TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "Hype")
        ])

        #expect(TokenPricingOverrideFeature.resolvedCoinGeckoID(
            token: token,
            override: nil,
            mappingsByIdentity: mappings) == "hype")
        #expect(TokenPricingOverrideFeature.resolvedPriceID(
            token: token,
            override: nil,
            mappingsByIdentity: mappings) == "hype")
    }

    @Test func `identity mapping is applied by the valuation`() {
        let identity = Fixture.onchain(.hyperEVM, "0xfeed")
        let token = Fixture.token(onchainIdentity: identity, amount: 2)
        let mapping = TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "hype")

        let valued = Fixture.valued(token, market: Fixture.market(live: ["hype": 30]), mappings: [mapping])

        #expect(valued.priceID == "hype")
        #expect(valued.value == 60)
        #expect(valued.source == .live)
    }

    @Test func `coin gecko id prefers the override then the asset then the mapping`() {
        let identity = Fixture.onchain(.hyperEVM, "0xfeed")
        let token = Fixture.token(coinGeckoId: " Asset-ID ", onchainIdentity: identity)
        let mappings = TokenIdentityMappingFeature.mappingsByIdentity([
            TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "mapped-id")
        ])
        let override = TokenPricingOverrideSnapshot(assetId: token.assetId, coinGeckoIdOverride: "override-id")

        #expect(TokenPricingOverrideFeature.resolvedCoinGeckoID(
            token: token,
            override: override,
            mappingsByIdentity: mappings) == "override-id")
        #expect(TokenPricingOverrideFeature.resolvedCoinGeckoID(
            token: token,
            override: nil,
            mappingsByIdentity: mappings) == "asset-id")
    }

    @Test func `manual price makes the price id irrelevant`() {
        let token = Fixture.token(coinGeckoId: "ethereum")
        #expect(TokenPricingOverrideFeature.resolvedPriceID(token: token, override: Fixture.manual(token, price: 5)) == nil)
    }

    /// A manual price changes the value, not the coin: the market price ID still resolves by I3,
    /// mappings included, and a platform chain keeps its onchain ID over the mapped one.
    @Test(arguments: [(Chain.degen, true), (Chain.ethereum, false)])
    func `market price id ignores the manual price`(chain: Chain, isMapped: Bool) {
        let identity = Fixture.onchain(chain, "0xfeed")
        let token = Fixture.token(onchainIdentity: identity)
        let mappings = TokenIdentityMappingFeature.mappingsByIdentity([
            TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "mapped-id")
        ])
        let override = Fixture.manual(token, price: 5)

        #expect(TokenPricingOverrideFeature.resolvedPriceID(token: token, override: override, mappingsByIdentity: mappings) == nil)
        #expect(TokenPricingOverrideFeature.marketPriceID(
            token: token,
            override: override,
            mappingsByIdentity: mappings) == (isMapped ? "mapped-id" : identity.historicalPriceID))
    }

    @Test(arguments: [(Decimal?.none, Decimal?.none), (0, nil), (-3, nil), (4, 4)])
    func `manual prices that are not positive are discarded`(price: Decimal?, kept: Decimal?) {
        #expect(TokenPricingOverrideFeature.sanitizedManualPrice(price) == kept)
    }

    @Test func `duplicate overrides for one asset keep the lowest override id`() throws {
        let assetId = UUID()
        let low = try TokenPricingOverrideSnapshot(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            assetId: assetId,
            manualPriceUSD: 1)
        let high = try TokenPricingOverrideSnapshot(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            assetId: assetId,
            manualPriceUSD: 2)

        #expect(TokenPricingOverrideFeature.overridesByAssetId([high, low])[assetId] == low)
        #expect(TokenPricingOverrideFeature.overridesByAssetId([low, high])[assetId] == low)
    }

    @Test func `price id that has no price is not swapped for another id`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(coinGeckoId: "usd-coin", onchainIdentity: identity, amount: 10, usdValue: 0)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["usd-coin": 1]))

        #expect(valued.source == .unpriced)
    }

    @Test func `solana contract case is preserved in the price id`() {
        let identity = Fixture.onchain(.solana, "MixedCaseMint111")
        let token = Fixture.token(onchainIdentity: identity, amount: 2)

        let valued = Fixture.valued(token, market: Fixture.market(live: [identity.historicalPriceID: 3]))

        #expect(valued.priceID == "asset:solana:MixedCaseMint111")
        #expect(valued.value == 6)
    }
}
