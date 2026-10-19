import Foundation
@testable import Portu
import PortuCore
import Testing

/// The shared fixture plus tokens that pin the Performance eligibility number changes (S10). Values
/// are USD and worked out by hand.
///
/// | Token | Role | Amount | `usdValue` | Spec value (source) |
/// |---|---|---|---|---|
/// | STALE | balance | 10 | 50, synced day 0 | 50 (sync; the day-0 close 0.05 loses) |
/// | FRESH | balance | 10 | 50, synced day −1 | 0.5 dust (the day-0 close 0.05 wins) |
/// | PLAUS | balance | 1 | 100 | 150 (onchain live 150: ratio 1.5 in USD) |
/// | NARROW | balance | 0.5 | 0.5 | 0.5 (onchain live 1) |
/// | NARROW | balance | 10 | 0.01 | 0 (onchain live 1: ratio 1000, unpriced) |
/// | PAIR | balance | 1 | 0.6 | 0.6 (live 0.6) |
/// | PAIR | balance | 1 | 0.6 | 0.6 (live 0.6) |
/// | HEDGE | supply, Aave V3 | 0.8 | 0.8 | 0.8 (live 1) |
/// | HEDGE | borrow, Aave V3 | 1000 | 1000 | −1000 (live 1) |
/// | RWD | reward, Lido | 5 | 50 | 0 (reward; live 10) |
enum PerformanceEligibilityFixture {
    typealias Fixture = PortfolioValuationFixture

    enum AssetID {
        static let stale = Fixture.uuid(9301)
        static let fresh = Fixture.uuid(9302)
        static let plausible = Fixture.uuid(9303)
        static let narrow = Fixture.uuid(9304)
        static let pair = Fixture.uuid(9305)
        static let hedge = Fixture.uuid(9306)
        static let reward = Fixture.uuid(9307)
    }

    static let plausibleIdentity = OnchainTokenIdentity(
        chain: .ethereum,
        contractAddress: "0x9a00000000000000000000000000000000009a01")
    static let narrowIdentity = OnchainTokenIdentity(
        chain: .ethereum,
        contractAddress: "0xa100000000000000000000000000000000000a11")

    static let extraInputs: [ValuationInput] = [
        input(1, .wallet, Fixture.token(
            AssetID.stale, "STALE", "Stale Close", .other, coinGeckoId: "stale-coin", amount: 10, usdValue: 50)),
        input(2, .wallet, Fixture.token(
            AssetID.fresh, "FRESH", "Fresh Close", .other, coinGeckoId: "fresh-coin", amount: 10, usdValue: 50,
            syncedAt: Fixture.noon(-1))),
        input(3, .wallet, Fixture.token(
            AssetID.plausible, "PLAUS", "Plausible", .other, onchainIdentity: plausibleIdentity, amount: 1, usdValue: 100)),
        input(4, .wallet, Fixture.token(
            AssetID.narrow, "NARROW", "Narrow", .other, onchainIdentity: narrowIdentity,
            amount: Fixture.decimal("0.5"), usdValue: Fixture.decimal("0.5"))),
        input(5, .wallet, Fixture.token(
            AssetID.narrow, "NARROW", "Narrow", .other, onchainIdentity: narrowIdentity,
            amount: 10, usdValue: Fixture.decimal("0.01"))),
        input(6, .wallet, Fixture.token(
            AssetID.pair, "PAIR", "Pair", .other, coinGeckoId: "pair-coin", amount: 1, usdValue: Fixture.decimal("0.6"))),
        input(7, .wallet, Fixture.token(
            AssetID.pair, "PAIR", "Pair", .other, coinGeckoId: "pair-coin", amount: 1, usdValue: Fixture.decimal("0.6"))),
        input(8, .aave, Fixture.token(
            AssetID.hedge, "HEDGE", "Hedge", .stablecoin, coinGeckoId: "hedge-coin", role: .supply,
            amount: Fixture.decimal("0.8"), usdValue: Fixture.decimal("0.8"))),
        input(9, .aave, Fixture.token(
            AssetID.hedge, "HEDGE", "Hedge", .stablecoin, coinGeckoId: "hedge-coin", role: .borrow,
            amount: 1000, usdValue: 1000)),
        input(10, .lido, Fixture.token(
            AssetID.reward, "RWD", "Reward Only", .defi, coinGeckoId: "reward-coin", role: .reward, amount: 5, usdValue: 50))
    ]

    static let inputs = Fixture.inputs + extraInputs

    static let livePricesUSD = Fixture.livePricesUSD.merging([
        plausibleIdentity.historicalPriceID: 150,
        narrowIdentity.historicalPriceID: 1,
        "pair-coin": Fixture.decimal("0.6"),
        "hedge-coin": 1,
        "reward-coin": 10
    ]) { _, new in new }

    static let historical = HistoricalMarketPrices(
        closesUSD: Fixture.historical.closesUSD.merging([
            "stale-coin": HistoricalClose(day: Fixture.day(0), price: Fixture.decimal("0.05")),
            "fresh-coin": HistoricalClose(day: Fixture.day(0), price: Fixture.decimal("0.05"))
        ]) { _, new in new },
        changes24h: Fixture.historical.changes24h)

    static func visible(
        rate: Decimal = 1,
        settings: TokenDashboardSettings = .defaults,
        inputs: [ValuationInput] = inputs) -> Set<UUID> {
        PerformanceDataShaping.visibleAssetIDs(Fixture.context(
            rate: rate,
            settings: settings,
            inputs: inputs,
            livePricesUSD: livePricesUSD,
            historical: historical))
    }

    private static func input(_ number: Int, _ slot: Fixture.PositionSlot, _ token: TokenEntry) -> ValuationInput {
        ValuationInput(tokenId: Fixture.uuid(9400 + number), token: token, position: slot.context)
    }
}

/// S10: the bottom panel's eligibility is `DashboardList(.net)` keyed by `assetId`, read through its
/// visible rows (AGENT-DECIDED 5 and 14). One row per asset, so its key differs from Overview's
/// price-ID + symbol rows (CRITIC C10).
struct PerformanceEligibilitySeamTests {
    private typealias Fixture = PortfolioValuationFixture
    private typealias Variant = PerformanceEligibilityFixture

    /// The fixture's eleven visible net asset rows. DAI and the USDT borrow are dust, BAD's onchain
    /// price is implausible, SCAM is ignored; TINY is dust with alwaysShow.
    private static let fixtureVisible: Set<UUID> = [
        Fixture.AssetID.usdc, Fixture.AssetID.eth, Fixture.AssetID.pepe, Fixture.AssetID.manual,
        Fixture.AssetID.link, Fixture.AssetID.uni, Fixture.AssetID.tiny, Fixture.AssetID.degen,
        Fixture.AssetID.otc, Fixture.AssetID.sol, Fixture.AssetID.arb
    ]

    /// "Number changes → Performance": eligibility is decided per asset row. The threshold is USD,
    /// so the display rate never moves the set.
    @Test func `the visible set is the net asset rows the display filter shows`() {
        let atOne = PerformanceDataShaping.visibleAssetIDs(Fixture.context())
        let atHalf = PerformanceDataShaping.visibleAssetIDs(Fixture.context(rate: Fixture.decimal("0.5")))
        let unpricedShown = PerformanceDataShaping.visibleAssetIDs(
            Fixture.context(settings: TokenDashboardSettings(hideUnpriced: false, hideDust: true)))
        let everything = PerformanceDataShaping.visibleAssetIDs(Fixture.context(settings: .showAll))

        #expect(atOne == Self.fixtureVisible)
        #expect(atHalf == Self.fixtureVisible)
        #expect(unpricedShown == Self.fixtureVisible.union([Fixture.AssetID.bad]))
        // With nothing hidden, every counted asset that is not ignored shows, per token or per row.
        #expect(everything == Self.fixtureVisible.union([Fixture.AssetID.bad, Fixture.AssetID.dai, Fixture.AssetID.usdt]))
    }

    /// "Number changes → Performance": sync-only holdings become eligible. OTC has no price ID and is
    /// valued at its sync value, 250.
    @Test func `a sync-only holding is eligible at its sync value`() {
        let visible = Variant.visible()

        #expect(visible.contains(Fixture.AssetID.otc))
    }

    /// "Number changes → Performance": a stale close loses to the sync value. A close beats the sync
    /// value only on a later UTC day (V1).
    @Test func `a stale close loses to the sync value`() {
        let visible = Variant.visible()

        #expect(visible.contains(Variant.AssetID.stale), "A same-day close must not make a 50 holding dust")
        #expect(!visible.contains(Variant.AssetID.fresh), "A close on a later day than the sync wins, and is dust")
    }

    /// "Number changes → Performance": plausibility compares USD with USD. At a display rate of 150 a
    /// display-currency price looked 150 times too large against the USD sync value.
    @Test func `plausibility compares the USD price with the USD sync value`() {
        let visible = Variant.visible(rate: 150)

        #expect(visible.contains(Variant.AssetID.plausible))
        #expect(!visible.contains(Fixture.AssetID.bad), "A USD ratio of 200 stays implausible")
    }

    /// "Number changes → Performance": the one narrowing case. With Hide unpriced off and Hide dust
    /// on, an asset with a priced dust token and an unpriced token is a dust row (F1: not every
    /// counted token is unpriced), so it is hidden. Per token, the unpriced one kept it visible.
    @Test func `an asset with priced dust and an unpriced token is hidden when only dust is hidden`() {
        let dustHidden = Variant.visible(settings: TokenDashboardSettings(hideUnpriced: false, hideDust: true))
        let nothingHidden = Variant.visible(settings: .showAll)

        #expect(!dustHidden.contains(Variant.AssetID.narrow))
        #expect(nothingHidden.contains(Variant.AssetID.narrow))
    }

    /// "Number changes → Performance": eligibility is decided per asset row. Two $0.60 tokens form a
    /// $1.20 row, and a hedged asset's filter value is its $1000 debt (F1), so neither is dust.
    @Test func `dust is judged on the whole asset row`() {
        let visible = Variant.visible()

        #expect(visible.contains(Variant.AssetID.pair))
        #expect(visible.contains(Variant.AssetID.hedge))
    }

    /// F2: ignored and not-counted rows are never dashboard rows, whatever the settings.
    @Test func `ignored and reward-only assets are never eligible`() {
        let visible = Variant.visible(settings: .showAll)

        #expect(!visible.contains(Fixture.AssetID.scam))
        #expect(!visible.contains(Variant.AssetID.reward))
    }
}
