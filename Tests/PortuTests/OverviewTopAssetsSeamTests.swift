import Foundation
@testable import Portu
import PortuCore
import Testing

/// The Top Assets donut seam on ad-hoc portfolios: aggregation, ids, the remainder, the hidden line
/// and F4 shares. Books are USD.
struct OverviewTopAssetsSeamTests {
    private typealias Fixture = OverviewValuationFixture

    @Test func `top assets aggregate by asset and put the residual into other`() throws {
        let btc = UUID()
        let eth = UUID()
        let sol = UUID()
        let usdc = UUID()
        let doge = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: btc, symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 60000),
                token(assetId: btc, symbol: "BTC", coinGeckoId: "bitcoin", amount: Fixture.decimal("0.5"), usdValue: 30000),
                token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 10, usdValue: 30000),
                token(assetId: sol, symbol: "SOL", coinGeckoId: "solana", amount: 100, usdValue: 10000),
                token(assetId: usdc, symbol: "USDC", coinGeckoId: "usd-coin", amount: 5000, usdValue: 5000),
                token(assetId: doge, symbol: "DOGE", coinGeckoId: "dogecoin", amount: 10000, usdValue: 2000),
                token(symbol: "ADA", coinGeckoId: "cardano", amount: 1000, usdValue: 500),
                token(symbol: "XRP", coinGeckoId: "ripple", amount: 100, usdValue: 200)
            ],
            livePricesUSD: [
                "bitcoin": 70000, "ethereum": 3000, "solana": 100, "usd-coin": 1, "dogecoin": Fixture.decimal("0.2"),
                "cardano": Fixture.decimal("0.5"), "ripple": 2
            ])

        let slices = OverviewFeature.topAssets(.assets, context: context).slices

        #expect(slices.map(\.label) == ["BTC", "ETH", "SOL", "USDC", "DOGE", "other"])
        #expect(slices.map(\.id) == [btc, eth, sol, usdc, doge].map(\.uuidString) + ["asset-residual"])
        #expect(slices.compactMap(\.displayPercent).reduce(0, +) == 100)
        #expect(try #require(slices.first).value == 105_000)
        #expect(try #require(slices.last).value == 700)
    }

    @Test func `top assets keep asset stable ids when coin gecko ids collide`() {
        let aave = UUID()
        let bridgedAave = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: aave, symbol: "AAVE", coinGeckoId: "aave", amount: 1, usdValue: 100),
                token(assetId: bridgedAave, symbol: "AAVE.e", coinGeckoId: "aave", amount: 1, usdValue: 90)
            ],
            livePricesUSD: ["aave": 100])

        let slices = OverviewFeature.topAssets(.assets, context: context).slices

        #expect(slices.map(\.id) == [aave.uuidString, bridgedAave.uuidString])
        #expect(Set(slices.map(\.id)).count == slices.count)
    }

    /// Newer-of (V1.5): with no live price the sync value holds unless a close is from a later day.
    @Test func `top assets take the sync value unless a close is newer`() {
        let rate = Fixture.decimal("0.9")
        let close = HistoricalMarketPrices(closesUSD: ["bitcoin": HistoricalClose(day: Fixture.day(0), price: 61000)])
        let value = { (syncedAt: Date, historical: HistoricalMarketPrices) in
            OverviewFeature.topAssets(
                .assets,
                context: Fixture.context(
                    tokens: [token(symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 60000, syncedAt: syncedAt)],
                    rate: rate,
                    historical: historical)).slices.map(\.value)
        }

        #expect(value(Fixture.noon(0), .empty) == [54000])
        #expect(value(Fixture.noon(0), close) == [54000])
        #expect(value(Fixture.noon(-1), close) == [54900])
    }

    @Test func `top assets include a sync only token at its sync value`() {
        let priced = UUID()
        let syncOnly = UUID()
        let context = Fixture.context(
            tokens: [
                token(assetId: syncOnly, symbol: "SYNC", amount: 1, usdValue: 10000),
                token(assetId: priced, symbol: "PRICED", coinGeckoId: "priced", amount: 2, usdValue: 2)
            ],
            livePricesUSD: ["priced": 3])

        let slices = OverviewFeature.topAssets(.assets, context: context).slices

        #expect(slices.map(\.id) == [syncOnly.uuidString, priced.uuidString])
        #expect(slices.map(\.label) == ["SYNC", "PRICED"])
        #expect(slices.map(\.value) == [10000, 6])
    }

    @Test func `top assets merge native eth from multiple chains`() throws {
        let mainnet = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0x0000000000000000000000000000000000000000")
        let base = OnchainTokenIdentity(chain: .base, contractAddress: "0x0000000000000000000000000000000000000000")
        let context = Fixture.context(
            tokens: [
                token(symbol: "ETH", name: "Ether", amount: 1, usdValue: 2000, onchainIdentity: mainnet),
                token(symbol: "ETH", name: "Ethereum", amount: Fixture.decimal("0.5"), usdValue: 1000, onchainIdentity: base)
            ],
            livePricesUSD: ["ethereum": 2300])

        let slices = OverviewFeature.topAssets(.assets, context: context).slices

        let slice = try #require(slices.first)
        #expect(slices.count == 1)
        #expect(slice.label == "ETH")
        #expect(slice.value == 3450)
    }

    @Test func `top assets carry asset logo urls`() throws {
        let logoURL = "https://img.example/stg.png"
        let context = Fixture.context(
            tokens: [token(symbol: "STG", coinGeckoId: "stargate-finance", amount: 10, usdValue: 2, logoURL: logoURL)],
            livePricesUSD: ["stargate-finance": Fixture.decimal("0.2")])

        let slice = try #require(OverviewFeature.topAssets(.assets, context: context).slices.first)

        #expect(slice.logoURL == logoURL)
    }

    @Test func `top assets convert the usd book once`() throws {
        let context = Fixture.context(
            tokens: [token(symbol: "BTC", coinGeckoId: "bitcoin", amount: 2, usdValue: 120_000)],
            rate: Fixture.decimal("0.9"),
            livePricesUSD: ["bitcoin": 55000])

        let slice = try #require(OverviewFeature.topAssets(.assets, context: context).slices.first)

        #expect(slice.value == 99000)
    }

    // MARK: - Category mode

    @Test func `category shares round to exactly one hundred`() {
        let context = Fixture.context(
            tokens: [
                token(symbol: "BTC", coinGeckoId: "btc", amount: 1, usdValue: 34),
                token(symbol: "ETH", coinGeckoId: "eth", amount: 1, usdValue: 33),
                token(symbol: "USDC", category: .stablecoin, coinGeckoId: "usdc", amount: 1, usdValue: 33)
            ],
            livePricesUSD: ["btc": 34, "eth": 33, "usdc": 33])

        let slices = OverviewFeature.topAssets(.category, context: context).slices

        #expect(slices.compactMap(\.displayPercent).reduce(0, +) == 100)
        #expect(slices.first?.label == "BTC")
        #expect(slices.first?.displayPercent == 34)
    }

    @Test func `category mode keeps the omitted categories in other`() throws {
        let context = Fixture.context(
            tokens: [
                token(symbol: "BTC", coinGeckoId: "btc", amount: 1, usdValue: 120),
                token(symbol: "ETH", coinGeckoId: "eth", amount: 1, usdValue: 100),
                token(symbol: "OTHER", category: .other, coinGeckoId: "other", amount: 1, usdValue: 90),
                token(symbol: "STABLE", category: .stablecoin, coinGeckoId: "stable", amount: 1, usdValue: 80),
                token(symbol: "DEFI", category: .defi, coinGeckoId: "defi", amount: 1, usdValue: 70),
                token(symbol: "MEME", category: .meme, coinGeckoId: "meme", amount: 1, usdValue: 60),
                token(symbol: "PRIV", category: .privacy, coinGeckoId: "priv", amount: 1, usdValue: 5),
                token(symbol: "FIAT", category: .fiat, coinGeckoId: "fiat", amount: 1, usdValue: 4),
                token(symbol: "SOL", coinGeckoId: "sol", amount: 1, usdValue: 3)
            ],
            livePricesUSD: [
                "btc": 120, "eth": 100, "other": 90, "stable": 80, "defi": 70, "meme": 60, "priv": 5, "fiat": 4, "sol": 3
            ])

        let slices = OverviewFeature.topAssets(.category, context: context).slices

        #expect(slices.map(\.label) == ["BTC", "ETH", "Other Tokens", "Stablecoins", "DeFi", "Meme", "other"])
        #expect(try #require(slices.last).value == 12)
        #expect(slices.compactMap(\.displayPercent).reduce(0, +) == 100)
    }

    @Test func `category residual id does not collide with the other tokens category`() {
        let context = Fixture.context(
            tokens: [
                token(symbol: "OTHER", category: .other, coinGeckoId: "other", amount: 1, usdValue: 90),
                token(symbol: "MAJOR", coinGeckoId: "major", amount: 1, usdValue: 80),
                token(symbol: "STABLE", category: .stablecoin, coinGeckoId: "stable", amount: 1, usdValue: 70),
                token(symbol: "DEFI", category: .defi, coinGeckoId: "defi", amount: 1, usdValue: 60),
                token(symbol: "MEME", category: .meme, coinGeckoId: "meme", amount: 1, usdValue: 50),
                token(symbol: "PRIV", category: .privacy, coinGeckoId: "priv", amount: 1, usdValue: 40),
                token(symbol: "BTC", coinGeckoId: "btc", amount: 1, usdValue: 35),
                token(symbol: "ETH", coinGeckoId: "eth", amount: 1, usdValue: 20)
            ],
            livePricesUSD: ["other": 90, "major": 80, "stable": 70, "defi": 60, "meme": 50, "priv": 40, "btc": 35, "eth": 20])

        let slices = OverviewFeature.topAssets(.category, context: context).slices

        #expect(slices.map(\.id).contains(PortfolioCategoryDefaults.fallbackCategoryID.uuidString))
        #expect(slices.map(\.id).contains("category-residual"))
        #expect(Set(slices.map(\.id)).count == slices.count)
        #expect(slices.compactMap(\.displayPercent).reduce(0, +) == 100)
    }

    // MARK: - Hidden line and shares

    /// F4: with a gross total of 0 there is no share to show, so every share is "—".
    @Test(arguments: [true, false])
    func `donut shares are a dash when the gross total is zero`(hideUnpriced: Bool) {
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: hideUnpriced, hideDust: true)
        let context = Fixture.context(
            tokens: [token(symbol: "GHOST", coinGeckoId: "ghost-coin", amount: 5, usdValue: 0)],
            settings: settings)

        let topAssets = OverviewFeature.topAssets(.assets, context: context)

        if hideUnpriced {
            #expect(topAssets.slices.isEmpty)
            #expect(topAssets.hidden?.unpricedCount == 1)
            #expect(topAssets.hiddenDisplayPercent == nil)
        } else {
            #expect(topAssets.slices.map(\.label) == ["GHOST"])
            #expect(topAssets.slices.map(\.displayPercent) == [nil])
            #expect(topAssets.hidden == nil)
        }
    }

    @Test func `donut shares are whole percentages when the gross total is positive`() {
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context())

        #expect(topAssets.slices.allSatisfy { $0.displayPercent != nil })
        #expect(topAssets.hiddenDisplayPercent == 0)
    }

    @Test func `donut hidden line is converted once at the display rate`() throws {
        let rate = Fixture.decimal("0.9")
        let usd = try #require(OverviewFeature.topAssets(.assets, context: Fixture.context()).hidden)
        let display = try #require(OverviewFeature.topAssets(.assets, context: Fixture.context(rate: rate)).hidden)

        #expect(display.gross == usd.gross * rate)
        #expect(display.gross == Fixture.decimal("0.45"))
        #expect(display.rowCount == usd.rowCount)
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        name: String? = nil,
        category: AssetCategory = .major,
        coinGeckoId: String? = nil,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil,
        logoURL: String? = nil,
        syncedAt: Date = Fixture.noon(0)) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: name ?? symbol,
            category: category,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: .balance,
            amount: amount,
            usdValue: usdValue,
            logoURL: logoURL,
            syncedAt: syncedAt)
    }
}
