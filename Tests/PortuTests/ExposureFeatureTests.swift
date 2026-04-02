import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct ExposureFeatureTests {
    // MARK: - B1: View Mode Toggle

    @Test func `view mode toggle updates state`() async {
        let store = TestStore(initialState: ExposureFeature.State()) {
            ExposureFeature()
        }

        await store.send(.viewModeChanged(true)) {
            $0.showByAsset = true
        }
        await store.send(.viewModeChanged(false)) {
            $0.showByAsset = false
        }
    }
}

// MARK: - B2: Category Exposure

struct ExposureCategoryTests {
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
                usdValue: 60000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .supply,
                amount: 10,
                usdValue: 30000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .borrow,
                amount: 3,
                usdValue: 9000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 5000,
                usdValue: 5000
            )
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        let major = categories.first { $0.id == "major" }
        let stable = categories.first { $0.id == "stablecoin" }

        #expect(major != nil)
        #expect(major?.spotAssets == 90000) // 60000 + 30000
        #expect(major?.liabilities == 9000)
        #expect(major?.spotNet == 81000) // 90000 - 9000

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
                usdValue: 96000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "RPL",
                name: "Rocket Pool",
                category: .defi,
                coinGeckoId: nil,
                role: .reward,
                amount: 5,
                usdValue: 150
            )
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        #expect(categories.count == 1) // Only major, no defi (reward excluded)
        #expect(categories[0].id == "major")
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
                usdValue: 60000
            )
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])

        #expect(categories.count == 1)
        #expect(categories[0].id == "major")
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
                usdValue: 100_000
            )
        ]

        let categories = ExposureFeature.computeCategoryExposure(
            tokens: tokens, prices: ["bitcoin": 65000]
        )

        #expect(categories[0].spotAssets == 130_000) // 2 * 65000
    }

    @Test func `maintains stable category ordering`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 1000,
                usdValue: 1000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 60000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "UNI",
                name: "Uniswap",
                category: .defi,
                coinGeckoId: nil,
                role: .balance,
                amount: 100,
                usdValue: 500
            )
        ]

        let categories = ExposureFeature.computeCategoryExposure(tokens: tokens, prices: [:])
        let ids = categories.map(\.id)

        // AssetCategory.allCases order: major, stablecoin, defi, ...
        #expect(ids == ["major", "stablecoin", "defi"])
    }
}

// MARK: - B3: Asset Exposure

struct ExposureAssetTests {
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
                usdValue: 30000
            ),
            TokenEntry(
                assetId: ethId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .borrow,
                amount: 3,
                usdValue: 9000
            )
        ]

        let assets = ExposureFeature.computeAssetExposure(tokens: tokens, prices: [:])

        #expect(assets.count == 1)
        #expect(assets[0].symbol == "ETH")
        #expect(assets[0].spotAssets == 30000)
        #expect(assets[0].liabilities == 9000)
        #expect(assets[0].spotNet == 21000)
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
                usdValue: 30000
            ),
            TokenEntry(
                assetId: btcId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 60000
            )
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
                usdValue: 100_000
            )
        ]

        let assets = ExposureFeature.computeAssetExposure(
            tokens: tokens, prices: ["bitcoin": 65000]
        )

        #expect(assets[0].spotAssets == 130_000) // 2 * 65000
    }
}

// MARK: - B4: Summary Totals

struct ExposureSummaryTests {
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
            CategoryExposure(id: "stablecoin", name: "Stablecoin", spotAssets: 50000, liabilities: 0)
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

// MARK: - B5: Token USD Value Resolution

struct ExposureTokenValueTests {
    @Test func `uses live price when available`() {
        let value = ExposureFeature.resolveTokenUSDValue(
            amount: 2, coinGeckoId: "bitcoin", usdValue: 100_000,
            prices: ["bitcoin": 65000]
        )

        #expect(value == 130_000)
    }

    @Test func `falls back to usd value when no live price`() {
        let value = ExposureFeature.resolveTokenUSDValue(
            amount: 100, coinGeckoId: nil, usdValue: 500,
            prices: [:]
        )

        #expect(value == 500)
    }

    @Test func `falls back when coinGeckoId not in prices`() {
        let value = ExposureFeature.resolveTokenUSDValue(
            amount: 10, coinGeckoId: "unknown-token", usdValue: 300,
            prices: ["bitcoin": 65000]
        )

        #expect(value == 300)
    }
}
