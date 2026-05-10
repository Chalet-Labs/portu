import Foundation
@testable import Portu
import PortuCore
import Testing

struct ExposureCategoryTests {
    @Test func `groups default buckets without sui while preserving defi and meme`() {
        let tokens = [
            token(symbol: "BTC", category: .major, usdValue: 100),
            token(symbol: "ETH", category: .major, usdValue: 90),
            token(symbol: "SOL", category: .major, usdValue: 50),
            token(symbol: "SUI", category: .major, usdValue: 40),
            token(symbol: "UNI", category: .defi, usdValue: 30),
            token(symbol: "PEPE", category: .meme, usdValue: 20),
            token(symbol: "XMR", category: .privacy, usdValue: 10),
            token(symbol: "CHF", category: .fiat, usdValue: 5),
            token(symbol: "USDC", category: .stablecoin, usdValue: 4),
            token(symbol: "OP", category: .governance, usdValue: 3),
            token(symbol: "UNKNOWN", category: .other, usdValue: 2)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let names = categories.map(\.name)

        #expect(names == [
            "BTC",
            "ETH",
            "SOL",
            "Other Tokens",
            "DeFi",
            "Meme",
            "Privacy",
            "Fiat",
            "Stablecoins"
        ])
    }

    @Test func `reference symbol buckets take precedence over stored fallback categories`() throws {
        let tokens = [
            token(symbol: "ETH", category: .other, usdValue: 100),
            token(symbol: "WETH", category: .defi, usdValue: 50),
            token(symbol: "UNI", category: .defi, usdValue: 25)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let eth = try #require(categories.first { $0.name == "ETH" })
        let defi = try #require(categories.first { $0.name == "DeFi" })

        #expect(eth.spotAssets == 150)
        #expect(defi.spotAssets == 25)
        #expect(categories.contains { $0.name == "Other Tokens" } == false)
    }

    @Test func `category share uses net exposure over total spot`() throws {
        let tokens = [
            token(symbol: "BTC", category: .major, usdValue: 60),
            token(symbol: "ETH", category: .major, usdValue: 40),
            token(symbol: "BTC", category: .major, role: .borrow, usdValue: 10)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let btc = try #require(categories.first { $0.name == "BTC" })
        let eth = try #require(categories.first { $0.name == "ETH" })

        #expect(btc.shareOfSpot == decimal("0.5"))
        #expect(eth.shareOfSpot == decimal("0.4"))
    }

    @Test func `category share is zero when total spot is zero`() throws {
        let tokens = [
            token(symbol: "BTC", category: .major, role: .borrow, usdValue: 10)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let btc = try #require(categories.first { $0.name == "BTC" })

        #expect(btc.shareOfSpot == 0)
    }

    @Test func `stablecoins are shown but excluded from net exposure`() {
        let tokens = [
            token(symbol: "BTC", category: .major, usdValue: 100),
            token(symbol: "USDC", category: .stablecoin, usdValue: 40)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let summary = ExposureFeature.computeSummary(from: categories)

        #expect(categories.contains { $0.name == "Stablecoins" })
        #expect(summary.netExposure == 100)
    }

    @Test func `unmatched major symbols use other tokens by default`() {
        let tokens = [
            token(symbol: "SUI", category: .major, usdValue: 10),
            token(symbol: "SOL", category: .major, usdValue: 10)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        #expect(categories.map(\.name) == ["Other Tokens", "SOL"])
    }

    @Test func `groups by category with spot and liabilities`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 60000),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .supply,
                amount: 10,
                usdValue: 30000),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .borrow,
                amount: 3,
                usdValue: 9000),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 5000,
                usdValue: 5000)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        let btc = categories.first { $0.name == "BTC" }
        let eth = categories.first { $0.name == "ETH" }
        let stable = categories.first { $0.name == "Stablecoins" }

        #expect(btc != nil)
        #expect(btc?.spotAssets == 60000)
        #expect(btc?.liabilities == 0)

        #expect(eth != nil)
        #expect(eth?.spotAssets == 30000)
        #expect(eth?.liabilities == 9000)
        #expect(eth?.netExposure == 21000)
        #expect(stable != nil)
        #expect(stable?.spotAssets == 5000)
        #expect(stable?.liabilities == 0)
    }

    @Test func `excludes rewards`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .stake,
                amount: 32,
                usdValue: 96000),
            TokenEntry(
                assetId: UUID(),
                symbol: "RPL",
                name: "Rocket Pool",
                category: .defi,
                coinGeckoId: nil,
                role: .reward,
                amount: 5,
                usdValue: 150)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        #expect(categories.count == 1) // Only major, no defi (reward excluded)
        #expect(categories[0].name == "ETH")
    }

    @Test func `omits categories with zero values`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 60000)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        #expect(categories.count == 1)
        #expect(categories[0].name == "BTC")
    }

    @Test func `uses live prices when available`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 2,
                usdValue: 100_000)
        ]

        let categories = ExposureFeature.computeCategoryExposure(
            tokens: tokens, prices: ["bitcoin": 65000])

        #expect(categories[0].spotAssets == 130_000) // 2 * 65000
    }

    @Test func `sorts categories by net exposure descending`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 1000,
                usdValue: 1000),
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 60000),
            TokenEntry(
                assetId: UUID(),
                symbol: "UNI",
                name: "Uniswap",
                category: .defi,
                coinGeckoId: nil,
                role: .balance,
                amount: 100,
                usdValue: 500)
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let ids = categories.map(\.name)

        #expect(ids == ["BTC", "Stablecoins", "DeFi"])
    }
}

// MARK: - Asset Exposure

struct ExposureAssetTests {
    @Test func `asset exposure carries logo url and share of spot`() throws {
        let assetId = UUID()
        let tokens = [
            token(
                assetId: assetId,
                symbol: "BTC",
                category: .major,
                usdValue: 60,
                logoURL: "https://img.example/btc.png"),
            token(symbol: "ETH", category: .major, usdValue: 40)
        ]

        let assets = ExposureFeature.computeAssetExposure(tokens: tokens, prices: [:])
        let btc = try #require(assets.first { $0.symbol == "BTC" })
        let eth = try #require(assets.first { $0.symbol == "ETH" })

        #expect(btc.logoURL == "https://img.example/btc.png")
        #expect(btc.shareOfSpot == decimal("0.6"))
        #expect(eth.shareOfSpot == decimal("0.4"))
    }

    @Test func `groups by asset with spot and liabilities`() {
        let ethId = UUID()
        let tokens = [
            TokenEntry(
                assetId: ethId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .supply,
                amount: 10,
                usdValue: 30000),
            TokenEntry(
                assetId: ethId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .borrow,
                amount: 3,
                usdValue: 9000)
        ]

        let assets = ExposureFeature.computeAssetExposure(tokens: tokens, prices: [:])

        #expect(assets.count == 1)
        #expect(assets[0].symbol == "ETH")
        #expect(assets[0].spotAssets == 30000)
        #expect(assets[0].liabilities == 9000)
        #expect(assets[0].netExposure == 21000)
    }

    @Test func `sorted by spot net descending`() {
        let btcId = UUID()
        let ethId = UUID()
        let tokens = [
            TokenEntry(
                assetId: ethId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 10,
                usdValue: 30000),
            TokenEntry(
                assetId: btcId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 60000)
        ]

        let assets = ExposureFeature.computeAssetExposure(tokens: tokens, prices: [:])

        #expect(assets[0].symbol == "BTC") // 60000 > 30000
        #expect(assets[1].symbol == "ETH")
    }

    @Test func `uses live prices`() {
        let btcId = UUID()
        let tokens = [
            TokenEntry(
                assetId: btcId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 2,
                usdValue: 100_000)
        ]

        let assets = ExposureFeature.computeAssetExposure(
            tokens: tokens, prices: ["bitcoin": 65000])

        #expect(assets[0].spotAssets == 130_000) // 2 * 65000
    }
}

private func token(
    assetId: UUID = UUID(),
    symbol: String,
    coinGeckoId: String? = nil,
    category: AssetCategory,
    role: TokenRole = .balance,
    amount: Decimal = 1,
    usdValue: Decimal = 1,
    logoURL: String? = nil) -> TokenEntry {
    TokenEntry(
        assetId: assetId,
        symbol: symbol,
        name: symbol,
        category: category,
        coinGeckoId: coinGeckoId,
        role: role,
        amount: amount,
        usdValue: usdValue,
        logoURL: logoURL)
}

private func decimal(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}
