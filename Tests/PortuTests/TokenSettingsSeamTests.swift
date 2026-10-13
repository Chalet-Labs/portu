import Foundation
@testable import Portu
import PortuCore
import Testing

/// The Token Settings seam (S8, F1, V5, T2) over the shared fixture and small variants of it. Every
/// value is worked out by hand in USD from the fixture tables.
///
/// On the shared fixture the list holds one row per asset, all fifteen: SCAM is ignored and listed
/// with no value, BAD is unpriced, DAI, TINY (always shown) and the USDT borrow are dust, and every
/// other row is priced.
struct TokenSettingsSeamTests {
    private typealias Fixture = PortfolioValuationFixture

    private static func result(
        _ context: ValuationContext,
        filter: TokenSettingsFilter = .all,
        searchText: String = "") -> TokenSettingsResult {
        TokenSettingsFeature.result(context, filter: filter, searchText: searchText)
    }

    private static func rowsByAsset(_ result: TokenSettingsResult) -> [UUID: TokenSettingsRow] {
        Dictionary(result.rows.map { ($0.assetId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func token(
        _ number: Int,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal = 0) -> TokenEntry {
        Fixture.token(
            Fixture.uuid(6000 + number),
            String(format: "S%03d", number),
            "Settings Token \(number)",
            .other,
            coinGeckoId: coinGeckoId,
            role: role,
            amount: amount,
            usdValue: usdValue)
    }

    /// S8: one row per asset over the active accounts, never only the visible ones, valued by the
    /// module. Number changes → Token Settings: "Values, sources and statuses come from the shared
    /// valuation" (sync-only, closes, mappings), "Ignored rows show no value", "Rewards no longer add
    /// to an asset", "Supply and borrow are priced per token".
    @Test func `every asset is listed with the module's value`() {
        let rows = Self.rowsByAsset(Self.result(Fixture.context()))
        let expected: [UUID: Decimal?] = [
            Fixture.AssetID.usdc: 1000,
            Fixture.AssetID.eth: 7500,
            Fixture.AssetID.pepe: 10,
            Fixture.AssetID.dai: Fixture.decimal("0.5"),
            Fixture.AssetID.manual: 100,
            Fixture.AssetID.link: 160,
            Fixture.AssetID.uni: 70,
            Fixture.AssetID.bad: 0,
            Fixture.AssetID.tiny: Fixture.decimal("0.3"),
            Fixture.AssetID.degen: 100,
            Fixture.AssetID.otc: 250,
            Fixture.AssetID.usdt: Fixture.decimal("-0.4"),
            Fixture.AssetID.sol: 1500,
            Fixture.AssetID.arb: 90,
            Fixture.AssetID.scam: nil
        ]

        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(rows.mapValues(\.value) == expected)
            #expect(rows[Fixture.AssetID.eth]?.amount == Fixture.decimal("2.5"))
            // The reward is not counted, so SOL's amount is its stake's.
            #expect(rows[Fixture.AssetID.sol]?.amount == 10)
        }
    }

    /// V5 and AGENT-DECIDED 11: the lead token's source, a close source, and "—" for an ignored row.
    @Test func `sources follow V5`() {
        let rows = Self.rowsByAsset(Self.result(Fixture.context()))

        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(rows[Fixture.AssetID.manual]?.pricingSource == .manual)
            #expect(rows[Fixture.AssetID.usdc]?.pricingSource == .live)
            #expect(rows[Fixture.AssetID.degen]?.pricingSource == .live)
            #expect(rows[Fixture.AssetID.link]?.pricingSource == .close)
            #expect(rows[Fixture.AssetID.uni]?.pricingSource == .syncTime)
            #expect(rows[Fixture.AssetID.otc]?.pricingSource == .syncTime)
            #expect(rows[Fixture.AssetID.bad]?.pricingSource == .unpriced)
            #expect(rows[Fixture.AssetID.scam].map { $0.pricingSource == nil } == true)
        }
    }

    /// F1 with alwaysShow as its own flag (AGENT-DECIDED 11). Number changes → Token Settings: "An
    /// always-show row keeps its dust or unpriced status in the counts".
    @Test func `statuses follow F1 with always show as its own flag`() {
        let result = Self.result(Fixture.context())
        let rows = Self.rowsByAsset(result)
        let expected: [UUID: RowStatus] = [
            Fixture.AssetID.usdc: .priced,
            Fixture.AssetID.eth: .priced,
            Fixture.AssetID.pepe: .priced,
            Fixture.AssetID.dai: .dust,
            Fixture.AssetID.manual: .priced,
            Fixture.AssetID.link: .priced,
            Fixture.AssetID.uni: .priced,
            Fixture.AssetID.bad: .unpriced,
            Fixture.AssetID.tiny: .dust,
            Fixture.AssetID.degen: .priced,
            Fixture.AssetID.otc: .priced,
            Fixture.AssetID.usdt: .dust,
            Fixture.AssetID.sol: .priced,
            Fixture.AssetID.arb: .priced,
            Fixture.AssetID.scam: .ignored
        ]

        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(rows.mapValues(\.status) == expected)
            #expect(Set(result.rows.filter(\.alwaysShow).map(\.assetId)) == [Fixture.AssetID.tiny])
            #expect(result.counts == TokenSettingsCounts(
                all: 15,
                unpriced: 1,
                belowThreshold: 3,
                ignored: 1,
                notCounted: 0,
                manualPrice: 1,
                mappedPriceSource: 0))
        }
    }

    /// S8 and T4: the ignored row stays listed, with status ignored, no value and no source.
    @Test func `an ignored row is listed with no value`() {
        let result = Self.result(Fixture.context())
        let scam = Self.rowsByAsset(result)[Fixture.AssetID.scam]

        #expect(scam?.isIgnored == true)
        #expect(Self.result(Fixture.context(), filter: .ignored).rows.map(\.assetId) == [Fixture.AssetID.scam])
        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(scam?.status == .ignored)
            #expect(scam.map { $0.value == nil } == true)
            #expect(scam.map { $0.pricingSource == nil } == true)
        }
    }

    /// S8 and U4: an asset with no counted token is Not Counted, valued Σ contributions = 0, with no
    /// source. Number changes → Token Settings: "A reward-only or zero-amount asset is Not counted".
    @Test func `a reward-only or zero-amount asset is not counted`() {
        let reward = Self.token(1, coinGeckoId: "reward-coin", role: .reward, amount: 5, usdValue: 50)
        let empty = Self.token(2, coinGeckoId: "empty-coin", amount: 0)
        let context = Fixture.context(tokens: [reward, empty], livePricesUSD: ["reward-coin": 10, "empty-coin": 3])
        let result = Self.result(context)
        let rows = Self.rowsByAsset(result)

        #expect(result.rows.count == 2)
        withKnownIssue("Token Settings still prices through the legacy rows") {
            for assetId in [reward.assetId, empty.assetId] {
                #expect(rows[assetId]?.status == .notCounted)
                #expect(rows[assetId]?.value == 0)
                #expect(rows[assetId].map { $0.pricingSource == nil } == true)
            }
            #expect(result.counts.notCounted == 2)
            #expect(Set(Self.result(context, filter: .notCounted).rows.map(\.assetId)) == [reward.assetId, empty.assetId])
        }
    }

    /// U4 and AGENT-DECIDED 3: ignore beats not counted on the badge, the count and the filter, even
    /// though F1 calls an ignored reward-only asset Not Counted.
    @Test func `an ignored reward-only asset counts as ignored`() {
        let reward = Self.token(3, coinGeckoId: "reward-coin", role: .reward, amount: 5, usdValue: 50)
        let context = Fixture.context(
            tokens: [reward],
            overrides: [TokenPricingOverrideSnapshot(assetId: reward.assetId, isIgnored: true)],
            livePricesUSD: ["reward-coin": 10])
        let result = Self.result(context)
        let row = result.rows.first

        #expect(row?.isIgnored == true)
        #expect(result.counts.ignored == 1)
        #expect(result.counts.notCounted == 0)
        #expect(Self.result(context, filter: .notCounted).rows.isEmpty)
        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(row?.status == .notCounted)
            #expect(row.map { $0.value == nil } == true)
        }
    }

    /// F1: the filter value is the larger of gross and debt, so a hedged asset with a $0.50 net is
    /// priced. Number changes → Token Settings: "A hedged asset is not dust".
    @Test func `a hedged asset is not dust`() {
        let supply = Self.token(4, coinGeckoId: "hedged-coin", role: .supply, amount: 1, usdValue: 100)
        let borrow = Self.token(4, coinGeckoId: "hedged-coin", role: .borrow, amount: Fixture.decimal("0.995"), usdValue: Fixture.decimal("99.5"))
        let context = Fixture.context(tokens: [supply, borrow], livePricesUSD: ["hedged-coin": 100])
        let row = Self.result(context).rows.first

        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(row?.status == .priced)
            #expect(row?.value == Fixture.decimal("0.5"))
        }
    }

    /// T1 units: USD prices go through the rate once, and the dust threshold stays $1 at any rate.
    /// Number changes → Token Settings: "Values, sources and statuses come from the shared valuation".
    @Test func `the rate is applied once and the threshold stays usd`() {
        let small = Self.token(5, coinGeckoId: "small-coin", amount: 1)
        let above = Self.token(6, coinGeckoId: "above-coin", amount: 1)
        let manual = Self.token(7, amount: 2)
        let live = Self.token(8, coinGeckoId: "live-coin", amount: 3)
        let context = Fixture.context(
            tokens: [small, above, manual, live],
            overrides: [TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 10)],
            rate: Fixture.decimal("0.5"),
            livePricesUSD: ["small-coin": Fixture.decimal("0.8"), "above-coin": Fixture.decimal("1.5"), "live-coin": 5])
        let rows = Self.rowsByAsset(Self.result(context))

        withKnownIssue("Token Settings still prices through the legacy rows") {
            #expect(rows[small.assetId]?.value == Fixture.decimal("0.4"))
            #expect(rows[small.assetId]?.status == .dust)
            #expect(rows[above.assetId]?.value == Fixture.decimal("0.75"))
            #expect(rows[above.assetId]?.status == .priced)
            #expect(rows[manual.assetId]?.value == 10)
            #expect(rows[live.assetId]?.value == Fixture.decimal("7.5"))
            #expect(rows[live.assetId]?.pricingSource == .live)
        }
    }

    /// AGENT-DECIDED 11: the manual-price count and filter read the override, so an ignored asset with
    /// a manual price still counts as Manual.
    @Test func `the manual price count reads the override`() {
        let ignored = Self.token(9, amount: 1)
        let context = Fixture.context(
            tokens: [ignored],
            overrides: [TokenPricingOverrideSnapshot(assetId: ignored.assetId, manualPriceUSD: 3, isIgnored: true)])
        let result = Self.result(context)

        #expect(result.counts.manualPrice == 1)
        #expect(result.counts.ignored == 1)
        #expect(Self.result(context, filter: .manualPrice).rows.map(\.assetId) == [ignored.assetId])
    }

    @Test func `search and the cap keep their numbers`() {
        let tokens = (0 ..< 120).map { index in
            Fixture.token(
                Fixture.uuid(6500 + index),
                String(format: "ROW%03d", index),
                "Row \(index)",
                .other,
                coinGeckoId: "row-\(index)",
                amount: 1,
                usdValue: 0)
        }
        let prices = Dictionary(uniqueKeysWithValues: (0 ..< 120).map { ("row-\($0)", Decimal(2)) })
        let result = Self.result(Fixture.context(tokens: tokens, livePricesUSD: prices), searchText: "row")

        #expect(result.totalMatches == 120)
        #expect(result.rows.count == 100)
        #expect(result.rows.first?.symbol == "ROW000")
        #expect(result.rows.last?.symbol == "ROW099")
        #expect(result.counts.all == 120)
    }
}
