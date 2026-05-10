import Foundation
@testable import Portu
import PortuCore
import Testing

struct ExposureSummaryTests {
    @Test func `asset count pill label describes asset rows`() {
        #expect(ExposureLabels.assetCountPillTitle == "Assets")
    }

    @Test func `computes totals from category exposures`() {
        let categories = [
            CategoryExposure(id: "major", name: "Major", spotAssets: 90000, liabilities: 9000),
            CategoryExposure(id: "stablecoin", name: "Stablecoin", spotAssets: 5000, liabilities: 0),
            CategoryExposure(id: "defi", name: "Defi", spotAssets: 1000, liabilities: 500)
        ]

        let summary = ExposureFeature.computeSummary(from: categories)

        #expect(summary.totalSpot == 96000) // 90000 + 5000 + 1000
        #expect(summary.totalLiabilities == 9500) // 9000 + 0 + 500
    }

    @Test func `net exposure excludes stablecoins`() {
        let categories = [
            CategoryExposure(id: "major", name: "Major", spotAssets: 90000, liabilities: 9000),
            CategoryExposure(
                id: "stablecoin",
                name: "Stablecoin",
                semanticRole: .stablecoin,
                spotAssets: 50000,
                liabilities: 0)
        ]

        let summary = ExposureFeature.computeSummary(from: categories)

        #expect(summary.netExposure == 81000) // 90000 - 9000, stablecoin excluded
    }

    @Test func `empty categories returns zero`() {
        let summary = ExposureFeature.computeSummary(from: [])

        #expect(summary.totalSpot == 0)
        #expect(summary.totalLiabilities == 0)
        #expect(summary.netExposure == 0)
    }
}

struct ExposureTokenValueTests {
    @Test func `uses live price when available`() {
        let value = ExposureFeature.resolveTokenUSDValue(
            amount: 2, coinGeckoId: "bitcoin", usdValue: 100_000,
            prices: ["bitcoin": 65000])

        #expect(value == 130_000)
    }

    @Test func `falls back to usd value when no live price`() {
        let value = ExposureFeature.resolveTokenUSDValue(
            amount: 100, coinGeckoId: nil, usdValue: 500,
            prices: [:])

        #expect(value == 500)
    }

    @Test func `falls back when coinGeckoId not in prices`() {
        let value = ExposureFeature.resolveTokenUSDValue(
            amount: 10, coinGeckoId: "unknown-token", usdValue: 300,
            prices: ["bitcoin": 65000])

        #expect(value == 300)
    }

    @Test func `price polling ids include positive and borrow tokens but exclude rewards`() {
        let tokens = [
            makeToken(symbol: "BTC", coinGeckoId: "bitcoin", category: .major, role: .balance),
            makeToken(symbol: "ETH", coinGeckoId: "ethereum", category: .major, role: .borrow),
            makeToken(symbol: "SOL", coinGeckoId: "solana", category: .major, role: .reward),
            makeToken(symbol: "UNKNOWN", coinGeckoId: nil, category: .other, role: .balance)
        ]

        let ids = ExposureFeature.pricePollingIDs(tokens: tokens, overrides: [])

        #expect(ids == ["bitcoin", "ethereum"])
    }

    @Test func `dashboard asset exposure filters unpriced dust and ignored tokens while keeping manual and pinned tokens`() throws {
        let visible = makeToken(symbol: "BTC", coinGeckoId: "bitcoin", category: .major, usdValue: 100)
        let unpriced = makeToken(symbol: "UNPRICED", category: .other, amount: 1, usdValue: 0)
        let dust = makeToken(symbol: "DUST", coinGeckoId: "dust", category: .other, amount: 1, usdValue: makeDecimal("0.50"))
        let ignored = makeToken(symbol: "IGNORED", coinGeckoId: "ignored", category: .defi, usdValue: 10)
        let manual = makeToken(symbol: "MANUAL", category: .meme, amount: 2, usdValue: 0)
        let pinned = makeToken(symbol: "PINNED", coinGeckoId: "pinned", category: .privacy, amount: 1, usdValue: makeDecimal("0.25"))

        let rows = ExposureFeature.computeDashboardAssetExposure(
            tokens: [visible, unpriced, dust, ignored, manual, pinned],
            prices: ["bitcoin": 100, "dust": makeDecimal("0.50"), "ignored": 10, "pinned": makeDecimal("0.25")],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 2),
                TokenPricingOverrideSnapshot(assetId: pinned.assetId, alwaysShow: true)
            ],
            settings: .defaults)

        #expect(rows.map(\.symbol) == ["BTC", "MANUAL", "PINNED"])
        #expect(try #require(rows.first { $0.symbol == "MANUAL" }).spotAssets == 4)
        #expect(try #require(rows.first { $0.symbol == "PINNED" }).spotAssets == makeDecimal("0.25"))
    }

    @Test func `price polling ids use overridden coin gecko ids`() {
        let mapped = makeToken(symbol: "MAP", coinGeckoId: "old-map", category: .other)

        let ids = ExposureFeature.pricePollingIDs(
            tokens: [mapped],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: " New-Map ")
            ])

        #expect(ids == ["new-map"])
    }

    @Test func `dashboard data reuses overrides for rows summary and polling ids`() throws {
        let btc = makeToken(symbol: "BTC", coinGeckoId: "bitcoin", category: .major, usdValue: 100)
        let ignored = makeToken(symbol: "IGNORED", coinGeckoId: "ignored", category: .defi, usdValue: 40)
        let manual = makeToken(symbol: "MANUAL", category: .meme, amount: 2, usdValue: 0)
        let mapped = makeToken(symbol: "MAP", coinGeckoId: "old-map", category: .privacy, usdValue: 3)

        let data = ExposureFeature.computeDashboardData(
            tokens: [btc, ignored, manual, mapped],
            prices: ["bitcoin": 100, "new-map": 4],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true),
                TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 2),
                TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: " New-Map ")
            ],
            settings: .defaults)

        #expect(data.assetRows.map(\.symbol) == ["BTC", "MANUAL", "MAP"])
        #expect(data.categoryRows.map(\.name) == ["BTC", "Meme", "Privacy"])
        #expect(try #require(data.assetRows.first { $0.symbol == "MANUAL" }).spotAssets == 4)
        #expect(try #require(data.assetRows.first { $0.symbol == "MAP" }).spotAssets == 4)
        #expect(data.summary.totalSpot == 108)
        #expect(data.pollingIDs == ["bitcoin", "ignored", "new-map"])
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
