import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - B5/B6: Reducer Tests

@MainActor
struct PortfolioHealthFeatureTests {
    @Test func `show all assets toggle updates state`() async {
        let store = TestStore(initialState: PortfolioHealthFeature.State()) {
            PortfolioHealthFeature()
        }

        await store.send(.showAllAssetsToggled) {
            $0.showAllAssets = true
        }
        await store.send(.showAllAssetsToggled) {
            $0.showAllAssets = false
        }
    }
}

// MARK: - B1: Asset Weight Computation

struct PortfolioHealthWeightTests {
    @Test func `computes weights sorted by percentage descending`() throws {
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
                role: .balance,
                amount: 10,
                usdValue: 30000),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 10000,
                usdValue: 10000)
        ]

        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: [:])

        let first = try #require(weights.first, "Expected at least 3 weights")
        #expect(weights.count == 3)
        #expect(first.symbol == "BTC")
        #expect(first.percentage == Decimal(60000) / Decimal(100_000))
        #expect(weights[1].symbol == "ETH")
        #expect(weights[1].percentage == Decimal(30000) / Decimal(100_000))
        #expect(weights[2].symbol == "USDC")
    }

    @Test func `groups tokens by symbol and name pair`() throws {
        let id = UUID()
        let tokens = [
            TokenEntry(
                assetId: id,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 5,
                usdValue: 15000),
            TokenEntry(
                assetId: id,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .supply,
                amount: 5,
                usdValue: 15000)
        ]

        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: [:])
        let first = try #require(weights.first, "Expected 1 weight for grouped ETH")

        #expect(weights.count == 1)
        #expect(first.symbol == "ETH")
        #expect(first.usdValue == 30000)
        #expect(first.percentage == 1)
    }

    @Test func `resolves price via coinGeckoId when usdValue is zero`() throws {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 2,
                usdValue: 0)
        ]
        let prices: [String: Decimal] = ["bitcoin": 50000]

        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: prices)
        let first = try #require(weights.first, "Expected 1 weight for BTC")

        #expect(weights.count == 1)
        #expect(first.usdValue == 100_000)
        #expect(first.percentage == 1)
    }

    @Test func `returns empty array when no tokens have value`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 0,
                usdValue: 0)
        ]

        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: [:])

        #expect(weights.isEmpty)
    }

    @Test func `excludes negative role tokens from weight`() throws {
        let tokens = [
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
                usdValue: 9000)
        ]

        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: [:])
        let first = try #require(weights.first, "Expected 1 weight for ETH net")

        #expect(weights.count == 1)
        #expect(first.usdValue == 21000) // 30000 - 9000
    }
}

// MARK: - B2: Concentration Risk

struct PortfolioHealthConcentrationTests {
    @Test func `detects assets exceeding threshold`() throws {
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 70000, percentage: #require(Decimal(string: "0.7"))),
            AssetWeight(symbol: "ETH", name: "Ethereum", usdValue: 20000, percentage: #require(Decimal(string: "0.2"))),
            AssetWeight(symbol: "USDC", name: "USD Coin", usdValue: 10000, percentage: #require(Decimal(string: "0.1")))
        ]

        let risks = try PortfolioHealthFeature.computeConcentrationRisks(
            weights: weights, threshold: #require(Decimal(string: "0.25")))

        let first = try #require(risks.first, "Expected 1 concentration risk")
        #expect(risks.count == 1)
        #expect(first.symbol == "BTC")
        #expect(first.percentage == Decimal(string: "0.7")!)
    }

    @Test func `returns empty when no asset exceeds threshold`() throws {
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 40000, percentage: #require(Decimal(string: "0.4"))),
            AssetWeight(symbol: "ETH", name: "Ethereum", usdValue: 30000, percentage: #require(Decimal(string: "0.3"))),
            AssetWeight(symbol: "USDC", name: "USD Coin", usdValue: 30000, percentage: #require(Decimal(string: "0.3")))
        ]

        let risks = try PortfolioHealthFeature.computeConcentrationRisks(
            weights: weights, threshold: #require(Decimal(string: "0.5")))

        #expect(risks.isEmpty)
    }

    @Test func `includes assets at exactly the threshold`() throws {
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 25000, percentage: #require(Decimal(string: "0.25")))
        ]

        let risks = try PortfolioHealthFeature.computeConcentrationRisks(
            weights: weights, threshold: #require(Decimal(string: "0.25")))

        #expect(risks.count == 1)
    }
}
