import Foundation
@testable import Portu
import PortuCore
import Testing

/// The Portfolio + Watchlist rows through the production seam on ad-hoc portfolios. Books are USD.
struct OverviewWatchlistSeamTests {
    private typealias Fixture = PortfolioValuationFixture

    @Test func `watchlist merges the top holdings with the watched ids`() {
        let btc = UUID()
        let eth = UUID()
        let assets = [
            asset(id: btc, symbol: "BTC", coinGeckoId: "bitcoin"),
            asset(id: eth, symbol: "ETH", coinGeckoId: "ethereum"),
            asset(symbol: "SUI", coinGeckoId: "sui"),
            asset(symbol: "XMR", coinGeckoId: "monero")
        ]
        let context = Fixture.context(
            tokens: [
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 6000),
                token(assetId: btc, symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.2"), usdValue: 12000)
            ],
            livePricesUSD: ["bitcoin": 70000, "ethereum": 3000, "sui": Fixture.decimal("1.1"), "monero": 350],
            liveChanges24h: ["bitcoin": Fixture.decimal("-0.03"), "ethereum": Fixture.decimal("0.01"), "monero": Fixture.decimal("0.02")])

        let rows = rows(context, assets: assets, watchlistIDs: ["monero", "bitcoin", "sui"], portfolioLimit: 2)

        #expect(rows.map(\.coinGeckoId) == ["bitcoin", "ethereum", "monero", "sui"])
        #expect(rows.map(\.isWatchlisted) == [true, false, true, true])
        #expect(rows[2].change24h == Fixture.decimal("0.02"))
    }

    @Test func `watchlist rows carry holding and watched logo urls`() throws {
        let holdingLogoURL = "https://img.example/stg.png"
        let watchedLogoURL = "https://img.example/gno.png"
        let context = Fixture.context(
            tokens: [token(symbol: "STG", coinGeckoId: "stargate-finance", amount: 10, usdValue: 2, logoURL: holdingLogoURL)],
            livePricesUSD: ["stargate-finance": Fixture.decimal("0.2"), "gnosis": 120])

        let rows = rows(context, assets: [asset(symbol: "GNO", coinGeckoId: "gnosis", logoURL: watchedLogoURL)], watchlistIDs: ["gnosis"])

        #expect(try #require(rows.first { $0.symbol == "STG" }).logoURL == holdingLogoURL)
        #expect(try #require(rows.first { $0.symbol == "GNO" }).logoURL == watchedLogoURL)
    }

    @Test func `watchlist normalizes a holding coin gecko id for prices and the watched flag`() throws {
        let btc = UUID()
        let context = Fixture.context(
            tokens: [token(assetId: btc, symbol: "BTC", coinGeckoId: " Bitcoin ", amount: Fixture.decimal("0.5"), usdValue: 10)],
            livePricesUSD: ["bitcoin": 70000],
            liveChanges24h: ["bitcoin": Fixture.decimal("0.04")])

        let row = try #require(rows(context, watchlistIDs: ["bitcoin"], portfolioLimit: 1).first)

        #expect(row.id == btc.uuidString)
        #expect(row.coinGeckoId == "bitcoin")
        #expect(row.price == 70000)
        #expect(row.change24h == Fixture.decimal("0.04"))
        #expect(row.isWatchlisted)
    }

    @Test func `watchlist keeps distinct mixed case Solana mints apart`() {
        let upper = OnchainTokenIdentity(chain: .solana, contractAddress: "SoLanaMiNtCase")
        let lower = OnchainTokenIdentity(chain: .solana, contractAddress: "solanamintcase")
        let context = Fixture.context(
            tokens: [
                token(symbol: "CASE", amount: 1, usdValue: 2, onchainIdentity: upper),
                token(symbol: "CASE", amount: 1, usdValue: 3, onchainIdentity: lower)
            ],
            livePricesUSD: [upper.historicalPriceID: 2, lower.historicalPriceID: 3],
            liveChanges24h: [upper.historicalPriceID: Fixture.decimal("0.02"), lower.historicalPriceID: Fixture.decimal("0.03")])

        let rows = rows(context)

        #expect(rows.count == 2)
        #expect(Set(rows.compactMap(\.price)) == [2, 3])
        #expect(Set(rows.compactMap(\.change24h)) == [Fixture.decimal("0.02"), Fixture.decimal("0.03")])
    }

    @Test func `watchlist keeps distinct holdings that share a coin gecko id`() {
        let aave = UUID()
        let bridgedAave = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: aave, symbol: "AAVE", coinGeckoId: "aave", amount: 2, usdValue: 100),
                token(assetId: bridgedAave, symbol: "AAVE.e", coinGeckoId: "AAVE", amount: 1, usdValue: 90)
            ],
            livePricesUSD: ["aave": 100],
            liveChanges24h: ["aave": Fixture.decimal("0.02")])

        let rows = rows(context, watchlistIDs: ["aave"])

        #expect(rows.map(\.id) == [aave.uuidString, bridgedAave.uuidString])
        #expect(rows.map(\.assetId) == [aave, bridgedAave])
        #expect(rows.map(\.coinGeckoId) == ["aave", "aave"])
        #expect(rows.map(\.isWatchlisted) == [true, true])
    }

    @Test func `watchlist keeps an orphaned watched id removable`() throws {
        let context = Fixture.context(
            tokens: [],
            livePricesUSD: ["ghost-token": Fixture.decimal("1.23")],
            liveChanges24h: ["ghost-token": Fixture.decimal("-0.05")])

        let row = try #require(rows(context, watchlistIDs: ["ghost-token"]).first)

        #expect(row.id == "ghost-token")
        #expect(row.assetId == nil)
        #expect(row.symbol == "ghost-token")
        #expect(row.coinGeckoId == "ghost-token")
        #expect(row.price == Fixture.decimal("1.23"))
        #expect(row.change24h == Fixture.decimal("-0.05"))
        #expect(row.isWatchlisted)
    }

    /// Newer-of (V1.5): a holding with no price ID is valued from its sync value, so it is a held
    /// row whose price is that value over its amount (V5).
    @Test func `watchlist shows a sync only holding at its sync value`() throws {
        let local = UUID()
        let context = Fixture.context(tokens: [token(assetId: local, symbol: "LOCAL", amount: 4, usdValue: 100)])

        let row = try #require(rows(context).first)

        #expect(row.id == local.uuidString)
        #expect(row.price == 25)
        #expect(row.coinGeckoId == nil)
        #expect(row.change24h == nil)
    }

    @Test func `watchlist merges native eth from multiple chains`() throws {
        let mainnet = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0x0000000000000000000000000000000000000000")
        let base = OnchainTokenIdentity(chain: .base, contractAddress: "0x0000000000000000000000000000000000000000")
        let context = Fixture.context(
            tokens: [
                token(symbol: "ETH", name: "Ether", amount: 1, usdValue: 2000, onchainIdentity: mainnet),
                token(symbol: "ETH", name: "Ethereum", amount: Fixture.decimal("0.5"), usdValue: 1000, onchainIdentity: base)
            ],
            livePricesUSD: ["ethereum": 2300],
            liveChanges24h: ["ethereum": Fixture.decimal("0.03")])

        let rows = rows(context)

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.symbol == "ETH")
        #expect(row.price == 2300)
        #expect(row.change24h == Fixture.decimal("0.03"))
        #expect(row.coinGeckoId == "ethereum")
    }

    /// No live price yet: the holding is valued from its sync value, so its row shows that value per
    /// unit (V5) rather than no price.
    @Test func `watchlist prices an onchain holding with no live price from its sync value`() throws {
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0x3e5a801830d63bfd3feb2885533e27648dbc17a7")
        let amount = Decimal(259_014_540)
        let usdValue = Fixture.decimal("1166.53082792")
        let context = Fixture.context(tokens: [
            token(symbol: "BTC", name: "HarryPotterObamaSatoshi1Meme", amount: amount, usdValue: usdValue, onchainIdentity: identity)
        ])

        let rows = rows(context)

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.price == usdValue / amount)
    }

    @Test func `watchlist uses the live price and change of an unmapped onchain holding`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let context = Fixture.context(
            tokens: [token(symbol: "LOCAL", amount: 4, usdValue: 20, onchainIdentity: identity)],
            livePricesUSD: [identity.historicalPriceID: 3],
            liveChanges24h: [identity.historicalPriceID: Fixture.decimal("0.12")])

        let row = try #require(rows(context).first)

        #expect(row.symbol == "LOCAL")
        #expect(row.price == 3)
        #expect(row.change24h == Fixture.decimal("0.12"))
    }

    @Test func `watchlist leaves out a holding with an implausible onchain live price`() {
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xBad")
        let context = Fixture.context(
            tokens: [token(symbol: "BAD", amount: 1_000_000, usdValue: 10, onchainIdentity: identity)],
            livePricesUSD: [identity.historicalPriceID: 1_000_000],
            liveChanges24h: [identity.historicalPriceID: Fixture.decimal("0.1")])

        #expect(rows(context).isEmpty)
    }

    /// S3: held rows are ranked by net contribution and must be positive, so a holding whose debt
    /// outweighs it is not a held row.
    @Test func `watchlist leaves out a holding whose net contribution is not positive`() {
        let eth = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 1, usdValue: 3000),
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", role: .borrow, amount: 2, usdValue: 6000),
                token(symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.1"), usdValue: 7000)
            ],
            livePricesUSD: ["ethereum": 3000, "bitcoin": 70000])

        #expect(rows(context).map(\.symbol) == ["BTC"])
    }

    /// ETH is the larger holding gross (9000) but the smaller one net (3000), so BTC (7000) takes the
    /// only held row.
    @Test func `watchlist ranks held rows by net contribution, not gross`() {
        let eth = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 3, usdValue: 9000),
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", role: .borrow, amount: 2, usdValue: 6000),
                token(symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.1"), usdValue: 7000)
            ],
            livePricesUSD: ["ethereum": 3000, "bitcoin": 70000])

        #expect(rows(context, portfolioLimit: 1).map(\.symbol) == ["BTC"])
    }

    /// Decided 2026-10-12: an ignored asset leaves the watchlist entirely, as a held row and as a
    /// watched coin. A watched coin with no ignore still shows.
    @Test func `watchlist hides an ignored held asset that is also watched`() {
        let eth = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 6000),
                token(symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.1"), usdValue: 7000)
            ],
            overrides: [TokenPricingOverrideSnapshot(assetId: eth, isIgnored: true)],
            livePricesUSD: ["ethereum": 3000, "bitcoin": 70000, "solana": 150])

        let rows = rows(
            context,
            assets: [asset(id: eth, symbol: "ETH", coinGeckoId: "ethereum"), asset(symbol: "SOL", coinGeckoId: "solana")],
            watchlistIDs: ["ethereum", "solana"])

        #expect(rows.map(\.coinGeckoId) == ["bitcoin", "solana"])
        #expect(rows.map(\.isWatchlisted) == [false, true])
    }

    @Test func `watchlist hides a watched coin whose asset is ignored although it is not held`() {
        let eth = UUID()
        let context = Fixture.context(
            tokens: [],
            overrides: [TokenPricingOverrideSnapshot(assetId: eth, isIgnored: true)],
            livePricesUSD: ["ethereum": 3000, "solana": 150])

        let rows = rows(
            context,
            assets: [asset(id: eth, symbol: "ETH", coinGeckoId: "ethereum"), asset(symbol: "SOL", coinGeckoId: "solana")],
            watchlistIDs: ["ethereum", "solana"])

        #expect(rows.map(\.coinGeckoId) == ["solana"])
    }

    /// A watched ID no asset candidate carries (a mapped or legacy ID) is matched through the held
    /// tokens' price IDs instead.
    @Test func `watchlist hides a watched coin that only an ignored holding prices`() {
        let local = UUID()
        let context = Fixture.context(
            tokens: [token(assetId: local, symbol: "LOCAL", coinGeckoId: "local-coin", amount: 4, usdValue: 100)],
            overrides: [TokenPricingOverrideSnapshot(assetId: local, isIgnored: true)],
            livePricesUSD: ["local-coin": 25])

        #expect(rows(context, watchlistIDs: ["local-coin"]).isEmpty)
    }

    /// The user ignores an asset, not a coin: ignoring native USDC leaves the bridged USDC.e, priced
    /// under the same ID, on the watchlist. USDC is the candidate the row would prefer, so the row
    /// falls back to USDC.e.
    @Test func `watchlist shows a watched coin while one asset priced under it is not ignored`() throws {
        let usdc = UUID()
        let bridged = UUID()
        let context = Fixture.context(
            tokens: [],
            overrides: [TokenPricingOverrideSnapshot(assetId: usdc, isIgnored: true)],
            livePricesUSD: ["usd-coin": 1])

        let rows = rows(
            context,
            assets: [asset(id: usdc, symbol: "USDC", coinGeckoId: "usd-coin"), asset(id: bridged, symbol: "USDC.e", coinGeckoId: "usd-coin")],
            watchlistIDs: ["usd-coin"])

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.coinGeckoId == "usd-coin")
        #expect(row.symbol == "USDC.e")
        #expect(row.assetId == bridged)
        #expect(row.price == 1)
    }

    @Test func `watchlist hides a watched coin when every asset priced under it is ignored`() {
        let usdc = UUID()
        let bridged = UUID()
        let context = Fixture.context(
            tokens: [],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: usdc, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: bridged, isIgnored: true)
            ],
            livePricesUSD: ["usd-coin": 1])

        let rows = rows(
            context,
            assets: [asset(id: usdc, symbol: "USDC", coinGeckoId: "usd-coin"), asset(id: bridged, symbol: "USDC.e", coinGeckoId: "usd-coin")],
            watchlistIDs: ["usd-coin"])

        #expect(rows.isEmpty)
    }

    /// A held, non-ignored USDC outside the top held rows still prices `usd-coin`, so the ignored
    /// USDC.e (the only asset candidate) does not hide the watched coin.
    @Test func `watchlist shows a watched coin a non ignored holding outside the top rows prices`() {
        let usdc = UUID()
        let bridged = UUID()
        let context = Fixture.context(
            tokens: [
                token(symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.1"), usdValue: 7000),
                token(assetId: usdc, symbol: "USDC", coinGeckoId: "usd-coin", amount: 50, usdValue: 50),
                token(assetId: bridged, symbol: "USDC.e", coinGeckoId: "usd-coin", amount: 40, usdValue: 40)
            ],
            overrides: [TokenPricingOverrideSnapshot(assetId: bridged, isIgnored: true)],
            livePricesUSD: ["bitcoin": 70000, "usd-coin": 1])

        let rows = rows(
            context,
            assets: [asset(id: bridged, symbol: "USDC.e", coinGeckoId: "usd-coin")],
            watchlistIDs: ["usd-coin"],
            portfolioLimit: 1)

        #expect(rows.map(\.coinGeckoId) == ["bitcoin", "usd-coin"])
        #expect(rows.map(\.isWatchlisted) == [false, true])
        // Every candidate under the ID is ignored, so the row falls back to describing USDC.e.
        #expect(rows.last?.symbol == "USDC.e")
        #expect(rows.last?.assetId == bridged)
    }

    /// DEGEN has no CoinGecko ID of its own; only its identity mapping prices it under `degen-base`
    /// (I3), so the ignore reaches the watched coin through the mapped price ID.
    @Test func `watchlist hides a watched coin that only an ignored mapped holding prices`() {
        let degen = UUID()
        let identity = OnchainTokenIdentity(chain: .degen, contractAddress: "0xDegen")
        let context = Fixture.context(
            tokens: [token(assetId: degen, symbol: "DEGEN", amount: 10000, usdValue: 95, onchainIdentity: identity)],
            overrides: [TokenPricingOverrideSnapshot(assetId: degen, isIgnored: true)],
            mappings: [TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "degen-base")],
            livePricesUSD: ["degen-base": Fixture.decimal("0.01")])

        #expect(rows(context, watchlistIDs: ["degen-base"]).isEmpty)
    }

    /// A manual price changes the value, not the coin: the ignored DEGEN (mapped to `degen-base`) and
    /// the ignored native ETH are still priced under their market IDs, so the ignore hides the coin.
    @Test(arguments: [
        (OnchainTokenIdentity(chain: .degen, contractAddress: "0xDegen"), "degen-base"),
        (OnchainTokenIdentity.native(on: .arbitrum), "ethereum")
    ])
    func `watchlist hides a watched coin that only an ignored manually priced holding prices`(
        identity: OnchainTokenIdentity,
        coinGeckoId: String) {
        let holding = UUID()
        let degen = OnchainTokenIdentity(chain: .degen, contractAddress: "0xDegen")
        let context = Fixture.context(
            tokens: [token(assetId: holding, symbol: "HOLD", amount: 10, usdValue: 95, onchainIdentity: identity)],
            overrides: [TokenPricingOverrideSnapshot(assetId: holding, manualPriceUSD: 2, isIgnored: true)],
            mappings: [TokenIdentityMappingSnapshot(identity: degen, coinGeckoId: "degen-base")],
            livePricesUSD: [coinGeckoId: Fixture.decimal("0.01")])

        #expect(rows(context, watchlistIDs: [coinGeckoId]).isEmpty)
    }

    /// On a chain with a CoinGecko platform the market ID stays the onchain one (I3), so a mapping
    /// to the watched coin does not tie the ignored holding to it.
    @Test func `watchlist keeps a watched coin a manually priced platform chain holding is only mapped to`() {
        let holding = UUID()
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xMapped")
        let context = Fixture.context(
            tokens: [token(assetId: holding, symbol: "MAP", amount: 10, usdValue: 95, onchainIdentity: identity)],
            overrides: [TokenPricingOverrideSnapshot(assetId: holding, manualPriceUSD: 2, isIgnored: true)],
            mappings: [TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "mapped-coin")],
            livePricesUSD: ["mapped-coin": 3])

        #expect(rows(context, watchlistIDs: ["mapped-coin"]).map(\.coinGeckoId) == ["mapped-coin"])
    }

    /// The only asset candidate under `degen-base` is ignored, but a non-ignored DEGEN holding outside
    /// the top held rows is priced under it through its mapping, so the watched coin stays. A manual
    /// price on the holding (second case) does not change the coin it is priced under.
    @Test(arguments: [nil, Fixture.decimal("0.001")])
    func `watchlist shows a watched coin a non ignored mapped holding prices`(manualPrice: Decimal?) {
        let ignored = UUID()
        let degen = UUID()
        let identity = OnchainTokenIdentity(chain: .degen, contractAddress: "0xDegen")
        let context = Fixture.context(
            tokens: [
                token(symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.1"), usdValue: 7000),
                token(assetId: degen, symbol: "DEGEN", amount: 10000, usdValue: 95, onchainIdentity: identity)
            ],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignored, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: degen, manualPriceUSD: manualPrice)
            ],
            mappings: [TokenIdentityMappingSnapshot(identity: identity, coinGeckoId: "degen-base")],
            livePricesUSD: ["bitcoin": 70000, "degen-base": Fixture.decimal("0.01")])

        let rows = rows(
            context,
            assets: [asset(id: ignored, symbol: "DEGEN", coinGeckoId: "degen-base")],
            watchlistIDs: ["degen-base"],
            portfolioLimit: 1)

        #expect(rows.map(\.coinGeckoId) == ["bitcoin", "degen-base"])
        #expect(rows.map(\.isWatchlisted) == [false, true])
        #expect(rows.last?.symbol == "DEGEN")
        #expect(rows.last?.assetId == ignored)
    }

    /// Plan: a holding whose same-asset debt equals (1) or exceeds (2) its supply has no positive
    /// net, so it is no held row. Watched, it shows once as the watched coin with its market quote.
    @Test(arguments: [Decimal(1), Decimal(2)])
    func `a watched holding with no positive net shows once as the watched coin`(borrowed: Decimal) throws {
        let eth = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 1, usdValue: 3000),
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", role: .borrow, amount: borrowed, usdValue: 3000 * borrowed)
            ],
            livePricesUSD: ["ethereum": 3100],
            liveChanges24h: ["ethereum": Fixture.decimal("0.02")])

        let rows = rows(context, assets: [asset(id: eth, symbol: "ETH", coinGeckoId: "ethereum")], watchlistIDs: ["ethereum"])

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.id == "ethereum")
        #expect(row.coinGeckoId == "ethereum")
        #expect(row.assetId == eth)
        #expect(row.price == 3100)
        #expect(row.change24h == Fixture.decimal("0.02"))
        #expect(row.isWatchlisted)
    }

    private func rows(
        _ context: ValuationContext,
        assets: [OverviewAssetCandidate] = [],
        watchlistIDs: [String] = [],
        portfolioLimit: Int = 10) -> [OverviewPriceRowData] {
        OverviewFeature.watchlistRows(
            context,
            assets: assets,
            watchlistIDs: watchlistIDs,
            portfolioLimit: portfolioLimit)
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        name: String? = nil,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil,
        logoURL: String? = nil) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: name ?? symbol,
            category: .major,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue,
            logoURL: logoURL,
            syncedAt: Fixture.noon(0))
    }

    private func asset(
        id: UUID = UUID(),
        symbol: String,
        coinGeckoId: String,
        logoURL: String? = nil) -> OverviewAssetCandidate {
        OverviewAssetCandidate(id: id, symbol: symbol, name: symbol, category: .major, coinGeckoId: coinGeckoId, logoURL: logoURL)
    }
}
