import Foundation
@testable import Portu
import PortuCore
import Testing

/// The live-polling set through the production seam (S12): who is a candidate, the usable-price
/// check, the ranking and the watchlist append. Books are USD.
struct OverviewPollingSeamTests {
    private typealias Fixture = PortfolioValuationFixture

    private static let hideBoth = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)

    @Test func `polling combines the ranked holdings and the watchlist in a stable order`() {
        let context = Fixture.context(
            tokens: [
                token(symbol: "ETH", coinGeckoId: "ethereum", amount: 1, usdValue: 3000),
                token(symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 70000),
                token(symbol: "ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 6000),
                token(symbol: "BORROW", coinGeckoId: "borrow-token", role: .borrow, amount: 10, usdValue: 100),
                token(symbol: "REWARD", coinGeckoId: "reward-token", role: .reward, amount: 10, usdValue: 100),
                token(symbol: "ZERO", coinGeckoId: "zero-token", amount: 10, usdValue: 0)
            ],
            livePricesUSD: ["ethereum": 3000, "bitcoin": 70000, "borrow-token": 10])

        let ids = OverviewFeature.pricePollingIDs(context, watchlistIDs: ["solana", " Bitcoin ", "monero"])

        #expect(ids == ["bitcoin", "ethereum", "borrow-token", "zero-token", "solana", "monero"])
    }

    @Test func `polling skips ignored dust and unpriceable holdings`() {
        let ignored = token(symbol: "IGNORED", coinGeckoId: "ignored", amount: 1, usdValue: 10)
        let context = Fixture.context(
            tokens: [
                token(symbol: "VISIBLE", coinGeckoId: "visible", amount: 1, usdValue: 2),
                ignored,
                token(symbol: "DUST", coinGeckoId: "dust", amount: 1, usdValue: Fixture.decimal("0.25")),
                token(symbol: "UNPRICEABLE", amount: 1, usdValue: 0)
            ],
            overrides: [TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true)],
            livePricesUSD: ["visible": 2, "ignored": 10, "dust": Fixture.decimal("0.25")])

        let ids = OverviewFeature.pricePollingIDs(context, watchlistIDs: ["bitcoin"])

        #expect(ids == ["visible", "bitcoin"])
    }

    @Test func `polling skips a token the dashboard hides although it has a live price`() {
        let context = Fixture.context(
            tokens: [token(symbol: "DUST", coinGeckoId: "dust", amount: 1, usdValue: 5)],
            settings: Self.hideBoth,
            livePricesUSD: ["dust": Fixture.decimal("0.25")])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []).isEmpty)
    }

    /// Dust is judged on the displayed row (F2): two $0.60 ETH holdings form one visible $1.20 row,
    /// whether they are valued from the live price or from a close newer than their sync.
    @Test(arguments: [true, false])
    func `polling keeps holdings that are dust alone but form a visible row`(isLive: Bool) {
        let context = Fixture.context(
            tokens: [
                token(symbol: "ETH", coinGeckoId: "ethereum", amount: Fixture.decimal("0.0002"), usdValue: Fixture.decimal("0.5")),
                token(symbol: "ETH", coinGeckoId: "ethereum", amount: Fixture.decimal("0.0002"), usdValue: Fixture.decimal("0.5"))
            ],
            settings: Self.hideBoth,
            livePricesUSD: isLive ? ["ethereum": 3000] : [:],
            historical: isLive ? .empty : HistoricalMarketPrices(closesUSD: ["ethereum": HistoricalClose(day: Fixture.day(1), price: 3000)]))

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == ["ethereum"])
    }

    /// Health groups by symbol and name, so two $0.60 USDC holdings under two price IDs are one
    /// visible $1.20 Health row although each asset row is dust.
    @Test func `polling keeps holdings that form a visible health row`() {
        let context = Fixture.context(
            tokens: [
                token(symbol: "USDC", coinGeckoId: "usd-coin", amount: Fixture.decimal("0.6"), usdValue: Fixture.decimal("0.6")),
                token(symbol: "USDC", coinGeckoId: "usd-coin-bridged", amount: Fixture.decimal("0.6"), usdValue: Fixture.decimal("0.6"))
            ],
            settings: Self.hideBoth,
            livePricesUSD: ["usd-coin": 1, "usd-coin-bridged": 1])

        #expect(Set(OverviewFeature.pricePollingIDs(context, watchlistIDs: [])) == ["usd-coin", "usd-coin-bridged"])
    }

    /// One onchain asset held twice at a $0.60 sync value each: the row is visible, so the holdings
    /// are polled although each one alone is dust with no usable price.
    @Test func `polling keeps sync valued holdings that form a visible row`() {
        let asset = UUID()
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xSplit")
        let context = Fixture.context(
            tokens: [
                token(assetId: asset, symbol: "SPLIT", amount: 1, usdValue: Fixture.decimal("0.6"), onchainIdentity: identity),
                token(assetId: asset, symbol: "SPLIT", amount: 1, usdValue: Fixture.decimal("0.6"), onchainIdentity: identity)
            ],
            settings: Self.hideBoth)

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [identity.historicalPriceID])
    }

    /// A row's dust check uses its larger side (F2), so a $5 supply against a $5 same-asset borrow
    /// stays visible and polled. A lone $0.60 ETH stays dust although the ETH category slice, which
    /// WETH fills, shows.
    @Test func `polling judges each row by its larger side and never by its category`() {
        let offset = Fixture.context(
            tokens: [
                token(symbol: "ETH", coinGeckoId: "ethereum", amount: Fixture.decimal("0.002"), usdValue: 5),
                token(symbol: "ETH", coinGeckoId: "ethereum", role: .borrow, amount: Fixture.decimal("0.002"), usdValue: 5)
            ],
            settings: Self.hideBoth,
            livePricesUSD: ["ethereum": 2500])
        let lone = Fixture.context(
            tokens: [
                token(symbol: "ETH", coinGeckoId: "ethereum", amount: Fixture.decimal("0.0002"), usdValue: Fixture.decimal("0.6")),
                token(symbol: "WETH", coinGeckoId: "weth", amount: Fixture.decimal("0.002"), usdValue: 5)
            ],
            settings: Self.hideBoth,
            livePricesUSD: ["ethereum": 3000, "weth": 2500])

        #expect(OverviewFeature.pricePollingIDs(offset, watchlistIDs: []) == ["ethereum"])
        #expect(OverviewFeature.pricePollingIDs(lone, watchlistIDs: []) == ["weth"])
    }

    /// Neither has a usable price, so only the counted check keeps them out: a reward valued from its
    /// sync value, and a zero amount.
    @Test func `polling skips an uncounted token`() {
        let context = Fixture.context(
            tokens: [
                token(symbol: "REWARD", coinGeckoId: "reward-token", role: .reward, amount: 10, usdValue: 100),
                token(symbol: "EMPTY", coinGeckoId: "empty-token", amount: 0, usdValue: 50)
            ],
            settings: TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: false, hideDust: false))

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []).isEmpty)
    }

    @Test func `polling keeps a resolvable unpriced holding so it can recover`() {
        let context = Fixture.context(tokens: [token(symbol: "UNPRICED", coinGeckoId: "unpriced", amount: 1, usdValue: 0)])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == ["unpriced"])
    }

    @Test func `polling asks for an unmapped onchain holding by its onchain id`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let context = Fixture.context(tokens: [token(symbol: "LOCAL", amount: 2, usdValue: 8, onchainIdentity: identity)])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [identity.historicalPriceID])
    }

    @Test func `polling preserves a mixed case Solana mint`() {
        let identity = OnchainTokenIdentity(chain: .solana, contractAddress: "SoLanaMiNtCase")
        let context = Fixture.context(tokens: [token(symbol: "SOLTOKEN", amount: 2, usdValue: 8, onchainIdentity: identity)])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [identity.historicalPriceID])
    }

    @Test func `polling uses the canonical key of a known contract`() {
        let identity = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xAf88d065e77c8cC2239327C5EDb3A432268e5831")
        let context = Fixture.context(tokens: [token(symbol: "USDC", amount: 390, usdValue: 390, onchainIdentity: identity)])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [identity.historicalPriceID])
    }

    @Test func `polling ranks larger unpriced onchain holdings first`() {
        let low = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0x1111")
        let usdc = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xAf88d065e77c8cC2239327C5EDb3A432268e5831")
        let context = Fixture.context(
            tokens: [
                token(symbol: "LOW", amount: 1, usdValue: 2, onchainIdentity: low),
                token(symbol: "USDC", amount: 390, usdValue: 390, onchainIdentity: usdc)
            ],
            settings: Self.hideBoth)

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [usdc.historicalPriceID, low.historicalPriceID])
    }

    @Test func `polling caps the holdings but keeps every watchlist id`() {
        let context = Fixture.context(tokens: [
            token(symbol: "LOW", coinGeckoId: "low", amount: 1, usdValue: 10),
            token(symbol: "HIGH", coinGeckoId: "high", amount: 1, usdValue: 100),
            token(symbol: "MID", coinGeckoId: "mid", amount: 1, usdValue: 50)
        ])

        let ids = OverviewFeature.pricePollingIDs(context, watchlistIDs: ["watch", "high"], portfolioLimit: 2)

        #expect(ids == ["high", "mid", "watch"])
    }

    @Test func `polling ranks an implausible onchain price by its sync value`() {
        let nativeETH = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0x0000000000000000000000000000000000000000")
        let badIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xBadPrice")
        let context = Fixture.context(
            tokens: [
                token(symbol: "BAD", amount: 1_000_000, usdValue: 10, onchainIdentity: badIdentity),
                token(symbol: "ETH", amount: 1, usdValue: 3000, onchainIdentity: nativeETH)
            ],
            livePricesUSD: [badIdentity.historicalPriceID: 1_000_000])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: [], portfolioLimit: 1) == ["ethereum"])
    }

    @Test func `polling skips an onchain dust token with no usable price under hideDust`() {
        let dust = OnchainTokenIdentity(chain: .base, contractAddress: "0xDust")
        let visible = OnchainTokenIdentity(chain: .base, contractAddress: "0xVisible")
        let context = Fixture.context(
            tokens: [
                token(symbol: "DUST", amount: 2, usdValue: Fixture.decimal("0.25"), onchainIdentity: dust),
                token(symbol: "VISIBLE", amount: 2, usdValue: 8, onchainIdentity: visible)
            ],
            settings: Self.hideBoth)

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [visible.historicalPriceID])
    }

    /// The onchain dust gate applies only while the dashboard would hide the token anyway.
    @Test(arguments: [
        (TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true), true),
        (TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: false, hideDust: true), false),
        (TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: false), false)
    ])
    func `polling keeps onchain dust with no usable price when it is shown`(settings: TokenDashboardSettings, alwaysShow: Bool) {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xDust")
        let dust = token(symbol: "DUST", amount: 2, usdValue: Fixture.decimal("0.25"), onchainIdentity: identity)
        let context = Fixture.context(
            tokens: [dust],
            overrides: alwaysShow ? [TokenPricingOverrideSnapshot(assetId: dust.assetId, alwaysShow: true)] : [],
            settings: settings)

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == [identity.historicalPriceID])
    }

    /// LIVE is worth $80 and FALLBACK $70 in USD; the rate scales both, so the order never changes.
    @Test(arguments: [Decimal(1), Fixture.decimal("0.5")])
    func `polling ranks by usd value whatever the display rate`(rate: Decimal) {
        let context = Fixture.context(
            tokens: [
                token(symbol: "FALLBACK", coinGeckoId: "fallback-coin", amount: 1, usdValue: 70),
                token(symbol: "LIVE", coinGeckoId: "live-coin", amount: 1, usdValue: 0)
            ],
            rate: rate,
            livePricesUSD: ["live-coin": 80])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: [], portfolioLimit: 1) == ["live-coin"])
    }

    /// Plan change (#98): a CoinGecko dust holding whose only close is not newer than its sync keeps
    /// its sync value and is polled so it can get a price. A close on a later UTC day values it, and
    /// as hidden dust it is not polled.
    @Test(arguments: [(-1, true), (0, true), (1, false)])
    func `polling a dust coin depends on whether its close is newer than its sync`(closeDay: Int, isPolled: Bool) {
        let close = HistoricalClose(day: Fixture.day(closeDay), price: Fixture.decimal("0.6"))
        let context = Fixture.context(
            tokens: [token(symbol: "DST", coinGeckoId: "dust-coin", amount: 1, usdValue: Fixture.decimal("0.5"))],
            settings: Self.hideBoth,
            historical: HistoricalMarketPrices(closesUSD: ["dust-coin": close]))

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == (isPolled ? ["dust-coin"] : []))
    }

    @Test func `polling asks for the coin gecko override`() {
        let mapped = token(symbol: "MAP", coinGeckoId: "old-map", amount: 1, usdValue: 10)
        let context = Fixture.context(
            tokens: [mapped],
            overrides: [TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: " New-Map ")],
            livePricesUSD: ["new-map": 10])

        #expect(OverviewFeature.pricePollingIDs(context, watchlistIDs: []) == ["new-map"])
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: .major,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue,
            syncedAt: Fixture.noon(0))
    }
}
