import Foundation
@testable import Portu
import PortuCore
import Testing

/// The dust threshold is USD and never scaled by the display rate (spec Terms, F2), and dust is
/// judged on the displayed row after aggregation (F2), on every Overview list.
struct OverviewDustRateSeamTests {
    private typealias Fixture = OverviewValuationFixture

    /// $1.50 is above the $1 threshold although it shows as 0.75 at rate 0.5.
    @Test func `a token above the usd threshold stays visible at a rate that shows it below one`() {
        let context = Self.stable(usdValue: Fixture.decimal("1.5"), rate: Fixture.decimal("0.5"))
        let shown = Fixture.decimal("0.75")

        let tab = OverviewPositionProjection.tab(.idleStables, context: context, positions: Fixture.positions)
        #expect(tab.groups.flatMap(\.tokens).map(\.value) == [shown])
        #expect(tab.hidden == nil)
        let donut = OverviewFeature.topAssets(.assets, context: context)
        #expect(donut.slices.map(\.value) == [shown])
        #expect(donut.hidden == nil)
        let health = PortfolioHealthFeature.health(context)
        #expect(health.weights.map(\.usdValue) == [shown])
        #expect(health.hidden == nil)
        #expect(OverviewFeature.watchlistRows(context, assets: [], watchlistIDs: []).map(\.symbol) == ["SKY"])
    }

    /// $0.80 is dust although it shows as 1.60 at rate 2.
    @Test func `a token below the usd threshold stays hidden at a rate that shows it above one`() {
        let context = Self.stable(usdValue: Fixture.decimal("0.8"), rate: 2)
        let shown = Fixture.decimal("1.6")

        let tab = OverviewPositionProjection.tab(.idleStables, context: context, positions: Fixture.positions)
        #expect(tab.groups.isEmpty)
        #expect(tab.hidden?.gross == shown)
        let donut = OverviewFeature.topAssets(.assets, context: context)
        #expect(donut.slices.isEmpty)
        #expect(donut.hidden?.gross == shown)
        let health = PortfolioHealthFeature.health(context)
        #expect(health.weights.isEmpty)
        #expect(health.hidden?.gross == shown)
        #expect(OverviewFeature.watchlistRows(context, assets: [], watchlistIDs: []).isEmpty)
    }

    /// Two $0.60 ETH holdings on two chains are each dust, but they form one $1.20 row.
    @Test func `two dust tokens of one asset form one visible row`() throws {
        let tokens = [(601, Fixture.PositionSlot.wallet), (602, .degenWallet)].map { number, slot in
            Fixture.input(number, slot, Fixture.token(
                Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum",
                amount: Fixture.decimal("0.0002"), usdValue: Fixture.decimal("0.58")))
        }
        let context = Fixture.context(inputs: tokens)
        let row = Fixture.decimal("1.2")

        let donut = OverviewFeature.topAssets(.assets, context: context)
        #expect(donut.slices.map(\.label) == ["ETH"])
        #expect(donut.slices.map(\.value) == [row])
        #expect(donut.hidden == nil)
        let held = try #require(OverviewFeature.watchlistRows(context, assets: [], watchlistIDs: []).first)
        #expect(held.symbol == "ETH")
        #expect(held.price == 3000)
        let health = PortfolioHealthFeature.health(context)
        #expect(health.weights.map(\.usdValue) == [row])
        #expect(health.hidden == nil)
    }

    private static func stable(usdValue: Decimal, rate: Decimal) -> OverviewValuationContext {
        Fixture.context(
            tokens: [Fixture.token(UUID(), "SKY", "Sky Dollar", .stablecoin, coinGeckoId: "sky-dollar", amount: usdValue, usdValue: usdValue)],
            rate: rate,
            livePricesUSD: ["sky-dollar": 1])
    }
}
