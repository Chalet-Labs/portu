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
