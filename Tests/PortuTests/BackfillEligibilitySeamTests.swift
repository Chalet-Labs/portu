import Foundation
@testable import Portu
import PortuCore
import Testing

/// Backfill eligibility (S12, AGENT-DECIDED 15) over the shared fixture plus a few edge tokens. The
/// expected sets are today's: a token's value is its manual price × amount, else its sync value, and
/// the threshold is unscaled USD.
///
/// | Token | Amount | `usdValue` | Override | Selected (defaults) |
/// |---|---|---|---|---|
/// | NEG | 1 | −20 | | yes, by \|usdValue\| |
/// | ZERO | 0 | 5 | | never: amount 0 |
/// | NOPRICE | 1 | 0 | | only with Hide unpriced off |
/// | MDUST | 10 | 0 | manual 0.01 | only with Hide dust off; never a candidate (manual only) |
/// | ZMAN | 1 | 30 | manual 0 | yes, by sync value; never a candidate (raw manual check) |
/// | MCG | 1 | 0 | manual 5, CoinGecko `manual-listed` | yes, a candidate under the override ID |
/// | MOVR | 1 | 10 | CoinGecko `new-id` | yes, a candidate under the override ID |
///
/// Snapshot-only assets: SNAP (net 30) and SNAPDUST (net 0.4).
enum BackfillEligibilityFixture {
    typealias Fixture = PortfolioValuationFixture

    enum AssetID {
        static let negative = Fixture.uuid(9501)
        static let zeroAmount = Fixture.uuid(9502)
        static let noPrice = Fixture.uuid(9503)
        static let manualDust = Fixture.uuid(9504)
        static let zeroManual = Fixture.uuid(9505)
        static let manualListed = Fixture.uuid(9506)
        static let moved = Fixture.uuid(9507)
        static let snapshot = Fixture.uuid(9601)
        static let snapshotDust = Fixture.uuid(9602)
    }

    static let extraTokens: [TokenEntry] = [
        Fixture.token(AssetID.negative, "NEG", "Negative", .other, coinGeckoId: "neg-coin", amount: 1, usdValue: -20),
        Fixture.token(AssetID.zeroAmount, "ZERO", "Zero Amount", .other, coinGeckoId: "zero-coin", amount: 0, usdValue: 5),
        Fixture.token(AssetID.noPrice, "NOPRICE", "No Price", .other, coinGeckoId: "noprice-coin", amount: 1, usdValue: 0),
        Fixture.token(AssetID.manualDust, "MDUST", "Manual Dust", .other, coinGeckoId: "mdust-coin", amount: 10, usdValue: 0),
        Fixture.token(AssetID.zeroManual, "ZMAN", "Zero Manual", .other, coinGeckoId: "zman-coin", amount: 1, usdValue: 30),
        Fixture.token(AssetID.manualListed, "MCG", "Manual Listed", .other, amount: 1, usdValue: 0),
        Fixture.token(AssetID.moved, "MOVR", "Moved", .other, coinGeckoId: "old-id", amount: 1, usdValue: 10)
    ]

    /// The fixture's tokens in table order, then the edge tokens.
    static let tokens = Fixture.inputs.map(\.token) + extraTokens

    static let overrides = Fixture.overrides + [
        TokenPricingOverrideSnapshot(assetId: AssetID.manualDust, manualPriceUSD: Fixture.decimal("0.01")),
        TokenPricingOverrideSnapshot(assetId: AssetID.zeroManual, manualPriceUSD: 0),
        TokenPricingOverrideSnapshot(assetId: AssetID.manualListed, manualPriceUSD: 5, coinGeckoIdOverride: "manual-listed"),
        TokenPricingOverrideSnapshot(assetId: AssetID.moved, coinGeckoIdOverride: "new-id")
    ]

    static let snapshots = [
        HistoricalBackfillSnapshotEntry(
            assetId: AssetID.snapshot, coinGeckoId: "snap-coin", onchainIdentity: nil,
            amount: 3, borrowAmount: 0, usdValue: 30, borrowUsdValue: 0),
        HistoricalBackfillSnapshotEntry(
            assetId: AssetID.snapshotDust, coinGeckoId: "snapdust-coin", onchainIdentity: nil,
            amount: 4, borrowAmount: 0, usdValue: Fixture.decimal("0.4"), borrowUsdValue: 0)
    ]

    /// The three sets one backfill run selects.
    struct Selection: Equatable {
        var candidates: [String: [UUID]]
        var sources: [String: HistoricalBackfillPriceSource]
        var sourceAssetIDs: Set<UUID>
        var identities: [OnchainTokenIdentity]
    }

    static func select(settings: TokenDashboardSettings) -> Selection {
        let candidates = HistoricalBackfillCandidateResolver.candidates(
            tokens: tokens,
            snapshots: snapshots,
            overrides: overrides,
            mappings: Fixture.mappings,
            dashboardSettings: settings)
        return Selection(
            candidates: Dictionary(uniqueKeysWithValues: candidates.map { ($0.historicalPriceID, $0.assetIds) }),
            sources: Dictionary(uniqueKeysWithValues: candidates.map { ($0.historicalPriceID, $0.source) }),
            sourceAssetIDs: HistoricalBackfillCandidateResolver.sourceAssetIDs(
                tokens: tokens,
                snapshots: snapshots,
                overrides: overrides,
                dashboardSettings: settings),
            identities: HistoricalBackfillCandidateResolver.onchainIdentitiesNeedingResolution(
                tokens: tokens,
                snapshots: snapshots,
                overrides: overrides,
                mappings: Fixture.mappings,
                dashboardSettings: settings))
    }
}

/// "Number changes → Backfill": no change to the candidate, source or identity-resolution sets.
struct BackfillEligibilitySeamTests {
    private typealias Fixture = PortfolioValuationFixture
    private typealias Edge = BackfillEligibilityFixture

    /// Under the default settings, dust (DAI, the USDT borrow, MDUST, SNAPDUST), unpriced (NOPRICE),
    /// amount-0 (ZERO), reward (the SOL reward) and ignored (SCAM) tokens are not selected. BAD's
    /// onchain live price would be implausible, but backfill values without a market, so its sync
    /// value selects it, and it is the one identity left to resolve.
    @Test func `the default settings select today's candidate, source and identity sets`() {
        let selection = Edge.select(settings: .defaults)

        #expect(selection.sourceAssetIDs == Self.defaultSources)
        #expect(selection.candidates == Self.defaultCandidates)
        #expect(selection.sources == Self.defaultCandidates.keys.reduce(into: [:]) { sources, id in
            sources[id] = id == Fixture.badIdentity.historicalPriceID ? .zerion(Fixture.badIdentity) : .coingecko(id)
        })
        #expect(selection.identities == [Fixture.badIdentity])
    }

    /// With nothing hidden, the dust and unpriced tokens join; amount-0, reward and ignored tokens
    /// still never do.
    @Test func `showing everything adds dust and unpriced tokens and nothing else`() {
        let selection = Edge.select(settings: .showAll)

        #expect(selection.sourceAssetIDs == Self.defaultSources.union([
            Fixture.AssetID.dai, Fixture.AssetID.usdt, Edge.AssetID.noPrice, Edge.AssetID.manualDust, Edge.AssetID.snapshotDust
        ]))
        #expect(selection.candidates == Self.defaultCandidates.merging([
            "dai": [Fixture.AssetID.dai],
            "tether": [Fixture.AssetID.usdt],
            "noprice-coin": [Edge.AssetID.noPrice],
            "snapdust-coin": [Edge.AssetID.snapshotDust]
        ]) { _, new in new })
        #expect(selection.identities == [Fixture.badIdentity])
    }

    private static let defaultSources: Set<UUID> = [
        Fixture.AssetID.usdc, Fixture.AssetID.eth, Fixture.AssetID.pepe, Fixture.AssetID.manual,
        Fixture.AssetID.link, Fixture.AssetID.uni, Fixture.AssetID.bad, Fixture.AssetID.tiny,
        Fixture.AssetID.degen, Fixture.AssetID.otc, Fixture.AssetID.sol, Fixture.AssetID.arb,
        Edge.AssetID.negative, Edge.AssetID.zeroManual, Edge.AssetID.manualListed, Edge.AssetID.moved,
        Edge.AssetID.snapshot
    ]

    /// MNL (manual only), ZMAN (a manual price of 0, the raw check) and OTC (no price ID) are sources
    /// with no candidate.
    private static let defaultCandidates: [String: [UUID]] = [
        "usd-coin": [Fixture.AssetID.usdc],
        "ethereum": [Fixture.AssetID.eth],
        "pepe": [Fixture.AssetID.pepe],
        "chainlink": [Fixture.AssetID.link],
        "uniswap": [Fixture.AssetID.uni],
        Fixture.badIdentity.historicalPriceID: [Fixture.AssetID.bad],
        "tiny-coin": [Fixture.AssetID.tiny],
        "degen-base": [Fixture.AssetID.degen],
        "solana": [Fixture.AssetID.sol],
        "arbitrum": [Fixture.AssetID.arb],
        "neg-coin": [Edge.AssetID.negative],
        "manual-listed": [Edge.AssetID.manualListed],
        "new-id": [Edge.AssetID.moved],
        "snap-coin": [Edge.AssetID.snapshot]
    ]
}
