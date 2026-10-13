import Foundation
@testable import Portu
import PortuCore
import Testing

/// Health over every symbol + name group (S3): the concentration warnings and the chain count.
struct OverviewHealthSeamTests {
    private typealias Fixture = OverviewValuationFixture

    /// $300 with a $100 threshold: the $90 group is hidden dust, yet 30% of the portfolio.
    @Test func `concentration risks cover a hidden group`() {
        let settings = TokenDashboardSettings(minimumDashboardValue: 100, hideUnpriced: true, hideDust: true)
        let context = Fixture.context(
            tokens: [
                token("BIG", amount: 1, usdValue: 210),
                token("SMALL", amount: 1, usdValue: 90)
            ],
            settings: settings)

        let health = PortfolioHealthFeature.health(context)

        #expect(health.weights.map(\.symbol) == ["BIG"])
        #expect(health.hidden?.rowCount == 1)
        #expect(health.concentrationRisks.map(\.symbol) == ["BIG", "SMALL"])
        #expect(health.concentrationRisks.map(\.percentage) == [Fixture.decimal("0.7"), Fixture.decimal("0.3")])
        #expect(health.concentrationRisks.allSatisfy { $0.threshold == PortfolioHealthFeature.concentrationThreshold })
    }

    @Test func `concentration risks skip groups below the threshold`() {
        let context = Fixture.context(tokens: [
            token("A", amount: 1, usdValue: 50),
            token("B", amount: 1, usdValue: 30),
            token("C", amount: 1, usdValue: 20)
        ])

        let health = PortfolioHealthFeature.health(context)

        #expect(health.concentrationRisks.map(\.symbol) == ["A", "B"])
        #expect(PortfolioHealthFeature.health(Fixture.context()).concentrationRisks.map(\.symbol) == ["ETH"])
    }

    /// The Lido reward is valued (live 150) but not counted, and it is the only token on Solana.
    @Test func `health chain count ignores a chain whose only valued tokens are uncounted`() {
        let ethereum = Fixture.input(501, .wallet, Fixture.token(
            Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 2, usdValue: 5800))
        let reward = Fixture.input(502, .lido, Fixture.token(
            Fixture.AssetID.sol, "SOL", "Solana", .major, coinGeckoId: "solana", role: .reward, amount: 1, usdValue: 150))

        let health = PortfolioHealthFeature.health(Fixture.context(inputs: [ethereum, reward]))

        #expect(health.metrics.chainCount == 1)
        #expect(health.metrics.assetCount == 1)
    }

    /// NOPE has no price ID, so it is counted but unpriced, and it is the only token on Base.
    @Test func `health chain count ignores a chain whose only counted token is unpriced`() {
        let ethereum = Fixture.input(503, .wallet, Fixture.token(
            Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 2, usdValue: 5800))
        let unpriced = Fixture.input(504, .scamWallet, Fixture.token(
            Fixture.uuid(1504), "NOPE", "No Price", .other, amount: 5, usdValue: 0))

        let health = PortfolioHealthFeature.health(Fixture.context(inputs: [ethereum, unpriced]))

        #expect(health.metrics.chainCount == 1)
    }

    /// The ignored XYZ is a stablecoin, the valued XYZ of the same symbol and name is not. Ignored
    /// tokens contribute nothing to Health (S3), so the group is not a stablecoin.
    @Test func `an ignored token does not make its group a stablecoin`() {
        let ignored = Fixture.token(UUID(), "XYZ", "Xyz", .stablecoin, amount: 100, usdValue: 100)
        let context = Fixture.context(
            tokens: [ignored, Fixture.token(UUID(), "XYZ", "Xyz", .defi, amount: 1, usdValue: 50), token("ETH", amount: 1, usdValue: 50)],
            overrides: [TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true)])

        let health = PortfolioHealthFeature.health(context)

        #expect(health.weights.map(\.symbol).sorted() == ["ETH", "XYZ"])
        #expect(health.metrics.stablecoinRatio == 0)
    }

    /// Health reads counted tokens only (S3): a reward, or a balance with no amount, in the stablecoin
    /// category does not make the counted XYZ of the same symbol and name a stablecoin.
    @Test(arguments: [(TokenRole.reward, Decimal(100)), (.balance, 0)])
    func `an uncounted token does not make its group a stablecoin`(role: TokenRole, amount: Decimal) {
        let context = Fixture.context(tokens: [
            Fixture.token(UUID(), "XYZ", "Xyz", .stablecoin, role: role, amount: amount, usdValue: 100),
            Fixture.token(UUID(), "XYZ", "Xyz", .defi, amount: 1, usdValue: 50),
            token("ETH", amount: 1, usdValue: 50)
        ])

        let health = PortfolioHealthFeature.health(context)

        #expect(health.weights.map(\.symbol).sorted() == ["ETH", "XYZ"])
        #expect(health.metrics.stablecoinRatio == 0)
    }

    /// "AB" + "C" and "A" + "BC" are two groups whose concatenations are both "ABC".
    @Test func `health groups whose symbol and name concatenate alike keep distinct identities`() {
        let context = Fixture.context(tokens: [
            Fixture.token(UUID(), "AB", "C", .stablecoin, amount: 1, usdValue: 60),
            Fixture.token(UUID(), "A", "BC", .defi, amount: 1, usdValue: 40)
        ])

        let health = PortfolioHealthFeature.health(context)

        #expect(health.weights.map(\.symbol) == ["AB", "A"])
        #expect(Set(health.weights.map(\.id)).count == 2)
        #expect(Set(health.weightList(showAll: true).rows.map(\.id)).count == 2)
        #expect(Set(health.concentrationRisks.map(\.id)).count == 2)
        #expect(health.metrics.stablecoinRatio == Fixture.decimal("0.6"))
    }

    @Test func `health hidden line is converted once at the display rate`() throws {
        let rate = Fixture.decimal("0.9")
        let usd = try #require(PortfolioHealthFeature.health(Fixture.context()).hidden)
        let display = try #require(PortfolioHealthFeature.health(Fixture.context(rate: rate)).hidden)

        #expect(display.gross == usd.gross * rate)
        #expect(display.gross == Fixture.decimal("0.45"))
        #expect(display.rowCount == usd.rowCount)
    }

    private func token(_ symbol: String, amount: Decimal, usdValue: Decimal) -> TokenEntry {
        Fixture.token(UUID(), symbol, symbol, .defi, amount: amount, usdValue: usdValue)
    }
}
