import Foundation
import PortuCore
import Testing

/// Preparing resolves each input's override and price ID once, from the store's rows alone, so a
/// read model can do it per data change and value per price tick (#123). Preparing changes no value.
struct ValuationPreparedTests {
    private typealias Fixture = ValuationFixtures

    private static let mappedIdentity = Fixture.onchain(.degen, "0xde9e")
    private static let eth = Fixture.token("ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 5800)
    private static let manual = Fixture.token("MNL", coinGeckoId: "manual-coin", amount: 10, usdValue: 50)
    private static let ignored = Fixture.token("SCAM", coinGeckoId: "scam", amount: 1000, usdValue: 10)
    private static let renamed = Fixture.token("OLD", coinGeckoId: "old-id", amount: 3, usdValue: 30)
    private static let mapped = Fixture.token("DEGEN", onchainIdentity: mappedIdentity, amount: 10000, usdValue: 95)
    private static let synced = Fixture.token("OTC", amount: 1, usdValue: 400, syncedAt: Fixture.noon(-1))
    private static let closed = Fixture.token("LINK", coinGeckoId: "chainlink", amount: 5, usdValue: 60, syncedAt: Fixture.noon(-2))
    private static let borrow = Fixture.token("USDC", coinGeckoId: "usd-coin", role: .borrow, amount: 500, usdValue: 500)

    private static let inputs = [eth, manual, ignored, renamed, mapped, synced, closed, borrow].map { Fixture.input($0) }
    private static let overrides = [
        Fixture.manual(manual, price: 7),
        Fixture.ignore(ignored),
        TokenPricingOverrideSnapshot(assetId: renamed.assetId, coinGeckoIdOverride: " New-ID ")
    ]
    private static let mappings = [TokenIdentityMappingSnapshot(identity: mappedIdentity, coinGeckoId: "degen-base")]
    private static let market = Fixture.market(
        live: ["ethereum": 3000, "degen-base": Fixture.decimal("0.01"), "new-id": 12, "usd-coin": 1],
        closes: ["chainlink": Fixture.close(14, day: -1)],
        changes: ["ethereum": Fixture.decimal("0.25"), "chainlink": Fixture.decimal("-0.1")])

    @Test func `a prepared valuation equals the valuation of the raw inputs`() {
        let prepared = PortfolioValuation.prepare(Self.inputs, overrides: Self.overrides, mappings: Self.mappings)

        let expected = PortfolioValuation(inputs: Self.inputs, market: Self.market, overrides: Self.overrides, mappings: Self.mappings)

        #expect(PortfolioValuation(prepared: prepared, market: Self.market) == expected)
        #expect(expected.tokens.map(\.source) == [.live, .manual, .ignored, .live, .live, .sync, .close, .live])
    }

    @Test func `preparing resolves each override and price id from the rows alone`() {
        let prepared = PortfolioValuation.prepare(Self.inputs, overrides: Self.overrides, mappings: Self.mappings)

        #expect(prepared.map(\.input) == Self.inputs)
        #expect(prepared.map(\.priceID) == ["ethereum", nil, "scam", "new-id", "degen-base", nil, "chainlink", "usd-coin"])
        #expect(prepared.map { $0.override?.assetId } == [nil, Self.manual.assetId, Self.ignored.assetId, Self.renamed.assetId, nil, nil, nil, nil])
    }

    @Test func `a prepared input values with any later market`() {
        let prepared = PortfolioValuation.prepare(Self.inputs, overrides: Self.overrides, mappings: Self.mappings)
        let later = Fixture.market(live: ["ethereum": 3100, "chainlink": 15])

        #expect(PortfolioValuation(prepared: prepared, market: later)
            == PortfolioValuation(inputs: Self.inputs, market: later, overrides: Self.overrides, mappings: Self.mappings))
    }

    /// Each token is valued on its own, so a subset of a valuation is the valuation of that subset:
    /// a screen showing part of the portfolio filters the one valuation instead of valuing again.
    @Test(arguments: [
        Set<String>(["ETH", "USDC"]),
        Set<String>(["MNL", "SCAM", "DEGEN"]),
        Set<String>(["OTC", "LINK", "OLD"]),
        Set<String>()
    ])
    func `restricting a valuation equals valuing the subset`(symbols: Set<String>) {
        let prepared = PortfolioValuation.prepare(Self.inputs, overrides: Self.overrides, mappings: Self.mappings)
        let subset = prepared.filter { symbols.contains($0.input.token.symbol) }

        let restricted = PortfolioValuation(prepared: prepared, market: Self.market)
            .restricted { symbols.contains($0.token.symbol) }

        let expected = PortfolioValuation(prepared: subset, market: Self.market)
        #expect(restricted == expected)
        #expect(restricted.keyChanges(settings: .defaults) == expected.keyChanges(settings: .defaults))
    }
}
