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
                usdValue: 60000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 10,
                usdValue: 30000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 10000,
                usdValue: 10000
            )
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
                usdValue: 15000
            ),
            TokenEntry(
                assetId: id,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .supply,
                amount: 5,
                usdValue: 15000
            )
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
                usdValue: 0
            )
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
                usdValue: 0
            )
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
            )
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
            weights: weights, threshold: #require(Decimal(string: "0.25"))
        )

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
            weights: weights, threshold: #require(Decimal(string: "0.5"))
        )

        #expect(risks.isEmpty)
    }

    @Test func `includes assets at exactly the threshold`() throws {
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 25000, percentage: #require(Decimal(string: "0.25")))
        ]

        let risks = try PortfolioHealthFeature.computeConcentrationRisks(
            weights: weights, threshold: #require(Decimal(string: "0.25"))
        )

        #expect(risks.count == 1)
    }
}

// MARK: - B3: Diversification Metrics

struct PortfolioHealthDiversificationTests {
    @Test func `computes all metrics for a diversified portfolio`() throws {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 50000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 10,
                usdValue: 30000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 20000,
                usdValue: 20000
            )
        ]
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 50000, percentage: #require(Decimal(string: "0.5"))),
            AssetWeight(symbol: "ETH", name: "Ethereum", usdValue: 30000, percentage: #require(Decimal(string: "0.3"))),
            AssetWeight(symbol: "USDC", name: "USD Coin", usdValue: 20000, percentage: #require(Decimal(string: "0.2")))
        ]

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 2
        )

        #expect(metrics.assetCount == 3)
        #expect(metrics.chainCount == 2)
        #expect(metrics.stablecoinRatio == Decimal(string: "0.2")!) // 20000/100000
        // HHI = 0.5² + 0.3² + 0.2² = 0.25 + 0.09 + 0.04 = 0.38
        #expect(metrics.herfindahlIndex == Decimal(string: "0.38")!)
    }

    @Test func `empty portfolio returns zero metrics`() {
        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: [], weights: [], chainCount: 0
        )

        #expect(metrics.assetCount == 0)
        #expect(metrics.chainCount == 0)
        #expect(metrics.stablecoinRatio == 0)
        #expect(metrics.herfindahlIndex == 0)
    }

    @Test func `stablecoin ratio uses token category`() throws {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 50000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 25000,
                usdValue: 25000
            ),
            TokenEntry(
                assetId: UUID(),
                symbol: "DAI",
                name: "Dai",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 25000,
                usdValue: 25000
            )
        ]
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 50000, percentage: #require(Decimal(string: "0.5"))),
            AssetWeight(symbol: "USDC", name: "USD Coin", usdValue: 25000, percentage: #require(Decimal(string: "0.25"))),
            AssetWeight(symbol: "DAI", name: "Dai", usdValue: 25000, percentage: #require(Decimal(string: "0.25")))
        ]

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 1
        )

        #expect(metrics.stablecoinRatio == Decimal(string: "0.5")!) // 50000/100000
    }
}

// MARK: - B4: Risk Level Classification

struct PortfolioHealthRiskLevelTests {
    @Test func `high risk when HHI above 0_5`() throws {
        let metrics = try DiversificationMetrics(
            assetCount: 2,
            chainCount: 1,
            stablecoinRatio: 0,
            herfindahlIndex: #require(Decimal(string: "0.55"))
        )

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .high)
    }

    @Test func `medium risk when HHI between 0_25 and 0_5`() throws {
        let metrics = try DiversificationMetrics(
            assetCount: 3,
            chainCount: 2,
            stablecoinRatio: #require(Decimal(string: "0.2")),
            herfindahlIndex: #require(Decimal(string: "0.38"))
        )

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .medium)
    }

    @Test func `low risk when HHI at or below 0_25`() throws {
        let metrics = try DiversificationMetrics(
            assetCount: 5,
            chainCount: 3,
            stablecoinRatio: #require(Decimal(string: "0.3")),
            herfindahlIndex: #require(Decimal(string: "0.25"))
        )

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .low)
    }

    @Test func `empty portfolio is low risk`() {
        let metrics = DiversificationMetrics(
            assetCount: 0,
            chainCount: 0,
            stablecoinRatio: 0,
            herfindahlIndex: 0
        )

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .low)
    }
}
