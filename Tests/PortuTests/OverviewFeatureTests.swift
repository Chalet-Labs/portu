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
        #expect(slices.map(\.id) == [btc.uuidString, eth.uuidString, sol.uuidString, "asset-residual"])
        #expect(slices.map(\.displayPercent).reduce(0, +) == 100)
        #expect(try #require(slices.first).value == 105_000)
        #expect(try #require(slices.last).value == 7000)
    }

    @Test func `top asset slices keep asset stable ids when coin gecko ids collide`() {
        let aave = UUID()
        let bridgedAave = UUID()
        let tokens = [
            token(assetId: aave, symbol: "AAVE", coinGeckoId: "aave", amount: 1, usdValue: 100),
            token(assetId: bridgedAave, symbol: "AAVE.e", coinGeckoId: "aave", amount: 1, usdValue: 90)
        ]

        let slices = OverviewFeature.topAssetSlices(from: tokens, prices: [:], limit: 2)

        #expect(slices.map(\.id) == [aave.uuidString, bridgedAave.uuidString])
        #expect(Set(slices.map(\.id)).count == slices.count)
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

    @Test func `category slices preserve omitted values in other bucket`() throws {
        let tokens = [
            token(symbol: "MAJOR", category: .major, amount: 1, usdValue: 80),
            token(symbol: "STABLE", category: .stablecoin, amount: 1, usdValue: 70),
            token(symbol: "DEFI", category: .defi, amount: 1, usdValue: 60),
            token(symbol: "MEME", category: .meme, amount: 1, usdValue: 50),
            token(symbol: "PRIV", category: .privacy, amount: 1, usdValue: 40),
            token(symbol: "FIAT", category: .fiat, amount: 1, usdValue: 30),
            token(symbol: "GOV", category: .governance, amount: 1, usdValue: 20),
            token(symbol: "OTHER", category: .other, amount: 1, usdValue: 10)
        ]

        let slices = OverviewFeature.categorySlices(from: tokens, prices: [:], limit: 6)

        #expect(slices.map(\.label) == ["Major", "Stablecoin", "Defi", "Meme", "Privacy", "Fiat", "other"])
        #expect(try #require(slices.last).value == 30)
        #expect(slices.map(\.displayPercent).reduce(0, +) == 100)
    }

    @Test func `category residual bucket does not collide with visible other category`() {
        let tokens = [
            token(symbol: "OTHER", category: .other, amount: 1, usdValue: 90),
            token(symbol: "MAJOR", category: .major, amount: 1, usdValue: 80),
            token(symbol: "STABLE", category: .stablecoin, amount: 1, usdValue: 70),
            token(symbol: "DEFI", category: .defi, amount: 1, usdValue: 60),
            token(symbol: "MEME", category: .meme, amount: 1, usdValue: 50),
            token(symbol: "PRIV", category: .privacy, amount: 1, usdValue: 40),
            token(symbol: "GOV", category: .governance, amount: 1, usdValue: 30)
        ]

        let slices = OverviewFeature.categorySlices(from: tokens, prices: [:], limit: 6)

        #expect(slices.map(\.id).contains("other"))
        #expect(slices.map(\.id).contains("category-residual"))
        #expect(Set(slices.map(\.id)).count == slices.count)
        #expect(slices.map(\.displayPercent).reduce(0, +) == 100)
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

    @Test func `price rows normalize portfolio coin gecko ids for lookups and watchlist state`() throws {
        let btc = UUID()
        let tokens = [
            token(assetId: btc, symbol: "BTC", coinGeckoId: " Bitcoin ", amount: 0.5, usdValue: 10)
        ]

        let rows = OverviewFeature.priceRows(
            tokens: tokens,
            assets: [],
            prices: ["bitcoin": 70000],
            changes24h: ["bitcoin": 0.04],
            watchlistIDs: ["bitcoin"],
            portfolioLimit: 1)

        let row = try #require(rows.first)
        #expect(row.id == "bitcoin")
        #expect(row.coinGeckoId == "bitcoin")
        #expect(row.price == 70000)
        #expect(row.change24h == 0.04)
        #expect(row.isWatchlisted)
    }

    @Test func `price rows keep orphaned watchlist ids removable`() throws {
        let rows = OverviewFeature.priceRows(
            tokens: [],
            assets: [],
            prices: ["ghost-token": 1.23],
            changes24h: ["ghost-token": -0.05],
            watchlistIDs: ["ghost-token"],
            portfolioLimit: 10)

        let row = try #require(rows.first)
        #expect(row.id == "ghost-token")
        #expect(row.assetId == nil)
        #expect(row.symbol == "ghost-token")
        #expect(row.coinGeckoId == "ghost-token")
        #expect(row.price == 1.23)
        #expect(row.change24h == -0.05)
        #expect(row.isWatchlisted)
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

    @Test func `asset candidates are pre grouped by normalized coin gecko id`() throws {
        let preferred = asset(symbol: "AAVE", coinGeckoId: " aave ")
        let later = asset(symbol: "ZAAVE", coinGeckoId: "AAVE")

        let grouped = OverviewFeature.assetCandidatesByCoinGeckoId(from: [later, preferred])

        #expect(grouped.keys.sorted() == ["aave"])
        #expect(try #require(grouped["aave"]) == preferred)
    }

    @Test func `watchlist suggestions are deduplicated by normalized coin gecko id`() {
        let preferred = asset(symbol: "AAVE", coinGeckoId: " aave ")
        let duplicate = asset(symbol: "ZAAVE", coinGeckoId: "AAVE")
        let sol = asset(symbol: "SOL", coinGeckoId: "solana")

        let suggestions = OverviewFeature.watchlistSuggestions(
            assets: [duplicate, sol, preferred],
            watchlistIDs: ["solana"],
            query: "aave")

        #expect(suggestions == [preferred])
    }

    @Test func `price display uses compact dollar prefix and trims asset labels`() throws {
        #expect(OverviewPriceDisplay.assetLabel("wrappedsteth") == "wrappe")
        #expect(OverviewPriceDisplay.assetLabel("BTC") == "BTC")

        let price = try OverviewPriceDisplay.price(#require(Decimal(
            string: "2866.478",
            locale: Locale(identifier: "en_US_POSIX"))))
        #expect(price.hasPrefix("$ "))
        #expect(!price.contains("US$"))
        #expect(!price.contains("US $"))
    }

    @Test func `price display keeps precision for very small assets`() throws {
        let price = try OverviewPriceDisplay.price(#require(Decimal(
            string: "0.00000012",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(price == "$ 0.00000012")
    }

    @Test func `price countdown derives remaining seconds from last update`() {
        let lastUpdate = Date(timeIntervalSince1970: 100)

        #expect(OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: lastUpdate,
            refreshInterval: 60,
            now: Date(timeIntervalSince1970: 112.2)) == 48)
        #expect(OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: lastUpdate,
            refreshInterval: 60,
            now: Date(timeIntervalSince1970: 170)) == 0)
        #expect(OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: nil,
            refreshInterval: 60,
            now: lastUpdate) == 60)
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

    @Test func `price polling ids combine active portfolio and watchlist ids in stable order`() {
        let tokens = [
            token(symbol: "ETH", coinGeckoId: "ethereum", amount: 1, usdValue: 3000),
            token(symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 70000),
            token(symbol: "ETH", coinGeckoId: "ethereum", amount: 2, usdValue: 6000),
            token(symbol: "ZERO", coinGeckoId: "zero-token", amount: 10, usdValue: 0)
        ]

        let ids = OverviewFeature.pricePollingIDs(
            tokens: tokens,
            watchlistIDs: ["solana", " Bitcoin ", "monero"])

        #expect(ids == ["bitcoin", "ethereum", "monero", "solana", "zero-token"])
    }

    @Test func `position pricing normalizes coin gecko ids`() {
        #expect(OverviewPositionPricing.price(
            coinGeckoId: " Ethereum ",
            amount: 2,
            usdValue: 10,
            prices: ["ethereum": 3000]) == 3000)
        #expect(OverviewPositionPricing.tokenValue(
            coinGeckoId: " Ethereum ",
            amount: 2,
            usdValue: 10,
            prices: ["ethereum": 3000]) == 6000)
        #expect(OverviewPositionPricing.change24h(
            coinGeckoId: " Ethereum ",
            amount: 2,
            prices: ["ethereum": 3000],
            changes24h: ["ethereum": 0.05]) == 300)
    }

    @Test func `borrow change tone treats increasing liabilities as unfavorable`() {
        #expect(OverviewPositionChangeTone.tone(for: .borrow, change: 10) == .unfavorable)
        #expect(OverviewPositionChangeTone.tone(for: .borrow, change: -10) == .favorable)
        #expect(OverviewPositionChangeTone.tone(for: .balance, change: 10) == .favorable)
        #expect(OverviewPositionChangeTone.tone(for: .balance, change: -10) == .unfavorable)
    }

    @Test func `summary card empty text distinguishes futures placeholder`() {
        #expect(OverviewSummaryCardText.emptyState(for: "Futures") == "Coming soon")
        #expect(OverviewSummaryCardText.emptyState(for: "Deployed") == "No deployed positions")
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
