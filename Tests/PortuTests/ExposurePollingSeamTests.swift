import Foundation
@testable import Portu
import PortuCore
import Testing

/// Exposure's polled set (S12, decided 2026-10-13): a counted, non-ignored token with a price ID,
/// while its asset row is visible or while it has no usable price. No ranking, cap or watchlist.
struct ExposurePollingSeamTests {
    private typealias Fixture = PortfolioValuationFixture

    /// The shared fixture: DAI and the USDT borrow are live-priced dust on hidden rows, so they are
    /// not polled; UNI (sync) and BAD (implausible live price, unpriced) are polled to recover.
    /// MNL is manual, OTC has no price ID, SCAM is ignored and the SOL reward is not counted.
    @Test func `polling follows the asset table's visible rows`() {
        let ids = ExposureFeature.dashboard(Fixture.context()).pollingIDs

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(ids == [
                "arbitrum",
                Fixture.badIdentity.historicalPriceID,
                "chainlink",
                "degen-base",
                "ethereum",
                "pepe",
                "solana",
                "tiny-coin",
                "uniswap",
                "usd-coin"
            ].sorted())
        }
    }

    /// S12: an implausible onchain live price leaves the token unpriced, and it stays polled so it
    /// can recover, even though its row is hidden.
    @Test func `an implausible live price is still polled`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0x000000000000000000000000000000000000dead")
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [Fixture.token(
                Self.bonk,
                "BONK2.0",
                "BONK2.0",
                .meme,
                onchainIdentity: identity,
                amount: 1_000_000_000_000_000_000,
                usdValue: 5)],
            livePricesUSD: [identity.historicalPriceID: 1]))

        #expect(data.assetRows.isEmpty)
        #expect(data.pollingIDs == [identity.historicalPriceID])
        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.assetHidden?.rowCount == 1)
        }
    }

    /// Ignored, manual, reward and zero-amount tokens are never polled; a visible borrow is.
    @Test func `ignored manual reward and empty tokens are never polled`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(Self.ignored, "IGN", "Ignored", .defi, coinGeckoId: "ignored-coin", amount: 10, usdValue: 10),
                Fixture.token(Self.manual, "MAN", "Manual", .defi, coinGeckoId: "manual-coin", amount: 10, usdValue: 10),
                Fixture.token(Self.reward, "RWD", "Reward", .defi, coinGeckoId: "reward-coin", role: .reward, amount: 10, usdValue: 10),
                Fixture.token(Self.empty, "EMPTY", "Empty", .defi, coinGeckoId: "empty-coin", amount: 0, usdValue: 5),
                Fixture.token(Self.borrowed, "BRW", "Borrowed", .defi, coinGeckoId: "borrow-coin", role: .borrow, amount: 500, usdValue: 500)
            ],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: Self.ignored, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: Self.manual, manualPriceUSD: 2)
            ],
            livePricesUSD: ["ignored-coin": 1, "manual-coin": 1, "reward-coin": 1, "borrow-coin": 1]))

        #expect(data.pollingIDs == ["borrow-coin"])
    }

    /// Number changes → Exposure: "a dust CoinGecko token at its sync value is polled". A live
    /// priced dust token on a hidden row is not.
    @Test func `a dust token at its sync value is polled and a live priced dust token is not`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(Self.btc, "BTC", "Bitcoin", .major, coinGeckoId: "bitcoin", amount: Fixture.decimal("0.01"), usdValue: 500),
                Fixture.token(Self.syncDust, "SDUST", "Sync Dust", .other, coinGeckoId: "sync-dust", amount: 1, usdValue: Fixture.decimal("0.5")),
                Fixture.token(Self.liveDust, "LDUST", "Live Dust", .other, coinGeckoId: "live-dust", amount: 1, usdValue: Fixture.decimal("0.5"))
            ],
            livePricesUSD: ["bitcoin": 50000, "live-dust": Fixture.decimal("0.5")]))

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.assetRows.map(\.symbol) == ["BTC"])
            #expect(data.pollingIDs == ["bitcoin", "sync-dust"])
        }
    }

    /// A token in a visible row is polled by its overridden CoinGecko ID.
    @Test func `a visible token is polled by its overridden coin gecko id`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [Fixture.token(Self.mapped, "MAP", "Mapped", .privacy, coinGeckoId: "old-map", amount: 1, usdValue: 3)],
            overrides: [TokenPricingOverrideSnapshot(assetId: Self.mapped, coinGeckoIdOverride: " New-Map ")],
            livePricesUSD: ["new-map": 4]))

        #expect(data.pollingIDs == ["new-map"])
        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.assetRows.map(\.spotAssets) == [4])
        }
    }

    private static let bonk = Fixture.uuid(801)
    private static let ignored = Fixture.uuid(802)
    private static let manual = Fixture.uuid(803)
    private static let reward = Fixture.uuid(804)
    private static let empty = Fixture.uuid(805)
    private static let borrowed = Fixture.uuid(806)
    private static let btc = Fixture.uuid(807)
    private static let syncDust = Fixture.uuid(808)
    private static let liveDust = Fixture.uuid(809)
    private static let mapped = Fixture.uuid(810)
}
