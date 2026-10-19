import Foundation
@testable import Portu
import PortuCore
import Testing

struct ExposureCategoryTests {
    @Test func `category share uses net exposure over total spot`() throws {
        let tokens = [
            token(symbol: "BTC", category: .major, usdValue: 60),
            token(symbol: "ETH", category: .major, usdValue: 40),
            token(symbol: "BTC", category: .major, role: .borrow, usdValue: 10)
        ]

        let categories = ExposureFeature.dashboard(PortfolioValuationFixture.context(tokens: tokens)).categoryRows
        let btc = try #require(categories.first { $0.name == "BTC" })
        let eth = try #require(categories.first { $0.name == "ETH" })

        #expect(btc.shareOfSpot == decimal("0.5"))
        #expect(eth.shareOfSpot == decimal("0.4"))
    }

    @Test func `category share is a dash when total spot is zero`() throws {
        let tokens = [
            token(symbol: "BTC", category: .major, role: .borrow, usdValue: 10)
        ]

        let categories = ExposureFeature.dashboard(PortfolioValuationFixture.context(tokens: tokens)).categoryRows
        let btc = try #require(categories.first { $0.name == "BTC" })

        // Was 0: "% of spot" shows "—" when Spot ≤ 0 (plan, Number changes → Exposure; AGENT-DECIDED 6).
        #expect(btc.shareOfSpot == nil)
    }
}

// MARK: - Asset Exposure

struct ExposureAssetTests {
    @Test func `dashboard exposure excludes implausible onchain live prices`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0x000000000000000000000000000000000000dead")
        let token = TokenEntry(
            assetId: UUID(),
            symbol: "BONK2.0",
            name: "BONK2.0",
            category: .meme,
            coinGeckoId: nil,
            onchainIdentity: identity,
            role: .balance,
            amount: 1_000_000_000_000_000_000,
            usdValue: 5)

        let data = ExposureFeature.dashboard(PortfolioValuationFixture.context(
            tokens: [token],
            livePricesUSD: [identity.historicalPriceID: 1]))

        #expect(data.summary.totalSpot == 0)
        #expect(data.categoryRows.isEmpty)
        #expect(data.assetRows.isEmpty)
    }

    @Test func `dashboard exposure counts an implausible onchain price as zero when showing unpriced rows`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0x000000000000000000000000000000000000dead")
        let token = TokenEntry(
            assetId: UUID(),
            symbol: "BONK2.0",
            name: "BONK2.0",
            category: .meme,
            coinGeckoId: nil,
            onchainIdentity: identity,
            role: .balance,
            amount: 1_000_000_000_000_000_000,
            usdValue: 5)

        let data = ExposureFeature.dashboard(PortfolioValuationFixture.context(
            tokens: [token],
            settings: TokenDashboardSettings(minimumDashboardValue: 0, hideUnpriced: false, hideDust: false),
            livePricesUSD: [identity.historicalPriceID: 1]))

        // Was 5, the sync value: an implausible onchain price counts 0 and shows as a 0 row (S4;
        // plan, Number changes → Exposure).
        let row = try #require(data.assetRows.first)
        #expect(data.summary.totalSpot == 0)
        #expect(row.spotAssets == 0)
    }

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

        let assets = ExposureFeature.dashboard(PortfolioValuationFixture.context(tokens: tokens)).assetRows
        let btc = try #require(assets.first { $0.symbol == "BTC" })
        let eth = try #require(assets.first { $0.symbol == "ETH" })

        #expect(btc.logoURL == "https://img.example/btc.png")
        #expect(btc.shareOfSpot == decimal("0.6"))
        #expect(eth.shareOfSpot == decimal("0.4"))
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
