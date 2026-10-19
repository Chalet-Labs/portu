import Foundation
@testable import Portu
import PortuCore
import Testing

struct ExposureSummaryTests {
    @Test func `asset count pill label describes asset rows`() {
        #expect(ExposureLabels.assetCountPillTitle == "Assets")
    }
}

struct ExposureDashboardTests {
    @Test func `dashboard asset exposure filters unpriced dust and ignored tokens while keeping manual and pinned tokens`() throws {
        let visible = makeToken(symbol: "BTC", coinGeckoId: "bitcoin", category: .major, usdValue: 100)
        let unpriced = makeToken(symbol: "UNPRICED", category: .other, amount: 1, usdValue: 0)
        let dust = makeToken(symbol: "DUST", coinGeckoId: "dust", category: .other, amount: 1, usdValue: makeDecimal("0.50"))
        let ignored = makeToken(symbol: "IGNORED", coinGeckoId: "ignored", category: .defi, usdValue: 10)
        let manual = makeToken(symbol: "MANUAL", category: .meme, amount: 2, usdValue: 0)
        let pinned = makeToken(symbol: "PINNED", coinGeckoId: "pinned", category: .privacy, amount: 1, usdValue: makeDecimal("0.25"))

        let rows = ExposureFeature.dashboard(PortfolioValuationFixture.context(
            tokens: [visible, unpriced, dust, ignored, manual, pinned],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 2),
                TokenPricingOverrideSnapshot(assetId: pinned.assetId, alwaysShow: true)
            ],
            livePricesUSD: ["bitcoin": 100, "dust": makeDecimal("0.50"), "ignored": 10, "pinned": makeDecimal("0.25")])).assetRows

        #expect(rows.map(\.symbol) == ["BTC", "MANUAL", "PINNED"])
        #expect(try #require(rows.first { $0.symbol == "MANUAL" }).spotAssets == 4)
        #expect(try #require(rows.first { $0.symbol == "PINNED" }).spotAssets == makeDecimal("0.25"))
    }

    @Test func `dashboard data reuses overrides for rows summary and polling ids`() throws {
        let btc = makeToken(symbol: "BTC", coinGeckoId: "bitcoin", category: .major, usdValue: 100)
        let ignored = makeToken(symbol: "IGNORED", coinGeckoId: "ignored", category: .defi, usdValue: 40)
        let manual = makeToken(symbol: "MANUAL", category: .meme, amount: 2, usdValue: 0)
        let mapped = makeToken(symbol: "MAP", coinGeckoId: "old-map", category: .privacy, usdValue: 3)

        let data = ExposureFeature.dashboard(PortfolioValuationFixture.context(
            tokens: [btc, ignored, manual, mapped],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 2),
                TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: " New-Map ")
            ],
            livePricesUSD: ["bitcoin": 100, "new-map": 4]))

        #expect(data.assetRows.map(\.symbol) == ["BTC", "MANUAL", "MAP"])
        #expect(data.categoryRows.map(\.name) == ["BTC", "Meme", "Privacy"])
        #expect(try #require(data.assetRows.first { $0.symbol == "MANUAL" }).spotAssets == 4)
        #expect(try #require(data.assetRows.first { $0.symbol == "MAP" }).spotAssets == 4)
        #expect(data.summary.totalSpot == 108)
        #expect(data.pollingIDs == ["bitcoin", "new-map"])
    }

    @Test func `dashboard data polls resolvable unpriced holdings for recovery without showing rows`() {
        let unpriced = makeToken(symbol: "UNPRICED", coinGeckoId: "recoverable", category: .other, amount: 1, usdValue: 0)

        let data = ExposureFeature.dashboard(PortfolioValuationFixture.context(tokens: [unpriced]))

        #expect(data.assetRows.isEmpty)
        #expect(data.categoryRows.isEmpty)
        #expect(data.pollingIDs == ["recoverable"])
    }

    private func makeToken(
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

    private func makeDecimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
