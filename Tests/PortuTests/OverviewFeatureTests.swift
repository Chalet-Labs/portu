import Foundation
@testable import Portu
import PortuCore
import Testing

struct OverviewFeatureTests {
    @Test func `top assets aggregate by asset and put residual into other`() throws {
        let btc = UUID()
        let eth = UUID()
        let sol = UUID()
        let usdc = UUID()
        let doge = UUID()
        let tokens = [
            token(assetId: btc, symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 60000),
            token(assetId: btc, symbol: "BTC", coinGeckoId: "bitcoin", amount: 0.5, usdValue: 30000),
            token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 10, usdValue: 30000),
            token(assetId: sol, symbol: "SOL", coinGeckoId: "solana", amount: 100, usdValue: 10000),
            token(assetId: usdc, symbol: "USDC", coinGeckoId: "usd-coin", amount: 5000, usdValue: 5000),
            token(assetId: doge, symbol: "DOGE", coinGeckoId: "dogecoin", amount: 10000, usdValue: 2000)
        ]

        let slices = OverviewFeature.topAssetSlices(
            from: tokens,
            prices: ["bitcoin": 70000, "ethereum": 3000],
            limit: 3)

        #expect(slices.map(\.label) == ["BTC", "ETH", "SOL", "other"])
        #expect(slices.map(\.displayPercent).reduce(0, +) == 100)
        #expect(try #require(slices.first).value == 105_000)
        #expect(try #require(slices.last).value == 7000)
    }

    @Test func `category slices round display percentages to exactly one hundred`() {
        let tokens = [
            token(symbol: "BTC", category: .major, amount: 1, usdValue: 34),
            token(symbol: "ETH", category: .major, amount: 1, usdValue: 33),
            token(symbol: "USDC", category: .stablecoin, amount: 1, usdValue: 33)
        ]

        let slices = OverviewFeature.categorySlices(from: tokens, prices: [:], limit: 6)

        #expect(slices.map(\.displayPercent).reduce(0, +) == 100)
        #expect(slices.first?.label == "Major")
        #expect(slices.first?.displayPercent == 67)
    }

    @Test func `price rows merge top portfolio assets with watchlist ids`() {
        let btc = UUID()
        let eth = UUID()
        let sui = UUID()
        let xmr = UUID()
        let assets = [
            asset(id: btc, symbol: "BTC", coinGeckoId: "bitcoin"),
            asset(id: eth, symbol: "ETH", coinGeckoId: "ethereum"),
            asset(id: sui, symbol: "SUI", coinGeckoId: "sui"),
            asset(id: xmr, symbol: "XMR", coinGeckoId: "monero")
        ]
        let tokens = [
            token(assetId: eth, symbol: "ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 6000),
            token(assetId: btc, symbol: "BTC", coinGeckoId: "bitcoin", amount: 0.2, usdValue: 12000)
        ]

        let rows = OverviewFeature.priceRows(
            tokens: tokens,
            assets: assets,
            prices: ["bitcoin": 70000, "ethereum": 3000, "sui": 1.1, "monero": 350],
            changes24h: ["bitcoin": -0.03, "ethereum": 0.01, "monero": 0.02],
            watchlistIDs: ["monero", "bitcoin", "sui"],
            portfolioLimit: 2)

        #expect(rows.map(\.coinGeckoId) == ["bitcoin", "ethereum", "monero", "sui"])
        #expect(rows[0].isWatchlisted)
        #expect(!rows[1].isWatchlisted)
        #expect(rows[2].change24h == 0.02)
    }

    @Test func `price rows include top portfolio assets without coin gecko ids`() throws {
        let localAsset = UUID()
        let tokens = [
            token(assetId: localAsset, symbol: "LOCAL", amount: 4, usdValue: 100)
        ]

        let rows = OverviewFeature.priceRows(
            tokens: tokens,
            assets: [],
            prices: [:],
            changes24h: [:],
            watchlistIDs: [],
            portfolioLimit: 10)

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.symbol == "LOCAL")
        #expect(row.price == 25)
        #expect(row.coinGeckoId == nil)
    }

    @Test func `price display uses compact dollar prefix and trims asset labels`() throws {
        #expect(OverviewPriceDisplay.assetLabel("wrappedsteth") == "wrappe")
        #expect(OverviewPriceDisplay.assetLabel("BTC") == "BTC")

        let price = try OverviewPriceDisplay.price(#require(Decimal(string: "2866.478")))
        #expect(price.hasPrefix("$ "))
        #expect(!price.contains("US$"))
        #expect(!price.contains("US $"))
    }

    @Test func `overview sync button uses compact reference metrics`() {
        #expect(OverviewSyncButtonStyleMetrics.iconName == "arrow.triangle.2.circlepath")
        #expect(OverviewSyncButtonStyleMetrics.height == 30)
        #expect(OverviewSyncButtonStyleMetrics.cornerRadius == 6)
        #expect(OverviewSyncButtonStyleMetrics.horizontalPadding == 11)
    }

    @Test func `watchlist persistence keeps order and uniqueness`() {
        let encoded = OverviewWatchlistStore.encode(["bitcoin", "ethereum", "bitcoin", "solana"])
        #expect(OverviewWatchlistStore.decode(encoded) == ["bitcoin", "ethereum", "solana"])

        let added = OverviewWatchlistStore.add("ethereum", to: ["bitcoin"])
        #expect(added == ["bitcoin", "ethereum"])

        let duplicate = OverviewWatchlistStore.add("bitcoin", to: added)
        #expect(duplicate == added)

        let removed = OverviewWatchlistStore.remove("bitcoin", from: duplicate)
        #expect(removed == ["ethereum"])
    }

    @Test func `price polling ids combine active portfolio and watchlist ids`() {
        let tokens = [
            token(symbol: "ETH", coinGeckoId: "ethereum", amount: 1, usdValue: 3000),
            token(symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 70000),
            token(symbol: "ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 6000)
        ]

        let ids = OverviewFeature.pricePollingIDs(
            tokens: tokens,
            watchlistIDs: ["solana", "bitcoin", "monero"])

        #expect(ids == ["bitcoin", "ethereum", "solana", "monero"])
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        category: AssetCategory = .major,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: category,
            coinGeckoId: coinGeckoId,
            role: role,
            amount: amount,
            usdValue: usdValue)
    }

    private func asset(
        id: UUID = UUID(),
        symbol: String,
        category: AssetCategory = .major,
        coinGeckoId: String) -> OverviewAssetCandidate {
        OverviewAssetCandidate(
            id: id,
            symbol: symbol,
            name: symbol,
            category: category,
            coinGeckoId: coinGeckoId)
    }
}
