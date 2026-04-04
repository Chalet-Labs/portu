import Foundation
@testable import Portu
import PortuCore
import Testing

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
                usdValue: 50000),
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
                amount: 20000,
                usdValue: 20000)
        ]
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 50000, percentage: #require(Decimal(string: "0.5"))),
            AssetWeight(symbol: "ETH", name: "Ethereum", usdValue: 30000, percentage: #require(Decimal(string: "0.3"))),
            AssetWeight(symbol: "USDC", name: "USD Coin", usdValue: 20000, percentage: #require(Decimal(string: "0.2")))
        ]

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 2)

        #expect(metrics.assetCount == 3)
        #expect(metrics.chainCount == 2)
        #expect(metrics.stablecoinRatio == Decimal(string: "0.2")!) // 20000/100000
        // HHI = 0.5² + 0.3² + 0.2² = 0.25 + 0.09 + 0.04 = 0.38
        #expect(metrics.herfindahlIndex == Decimal(string: "0.38")!)
    }

    @Test func `empty portfolio returns zero metrics`() {
        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: [], weights: [], chainCount: 0)

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
                usdValue: 50000),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 25000,
                usdValue: 25000),
            TokenEntry(
                assetId: UUID(),
                symbol: "DAI",
                name: "Dai",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .balance,
                amount: 25000,
                usdValue: 25000)
        ]
        let weights = try [
            AssetWeight(symbol: "BTC", name: "Bitcoin", usdValue: 50000, percentage: #require(Decimal(string: "0.5"))),
            AssetWeight(symbol: "USDC", name: "USD Coin", usdValue: 25000, percentage: #require(Decimal(string: "0.25"))),
            AssetWeight(symbol: "DAI", name: "Dai", usdValue: 25000, percentage: #require(Decimal(string: "0.25")))
        ]

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 1)

        #expect(metrics.stablecoinRatio == Decimal(string: "0.5")!) // 50000/100000
    }

    @Test func `stablecoin ratio uses resolved values when live prices available`() throws {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 50000),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: "usd-coin",
                role: .balance,
                amount: 10000,
                usdValue: 10000)
        ]
        let prices: [String: Decimal] = try ["usd-coin": #require(Decimal(string: "1.05"))]
        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: prices)

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 1)

        // Resolved USDC = 10000 * 1.05 = 10500, total = 60500
        #expect(metrics.stablecoinRatio == Decimal(10500) / Decimal(60500))
    }

    @Test func `stablecoin ratio excludes borrowed stablecoins`() {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 50000),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .supply,
                amount: 20000,
                usdValue: 20000),
            TokenEntry(
                assetId: UUID(),
                symbol: "DAI",
                name: "Dai",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .borrow,
                amount: 5000,
                usdValue: 5000)
        ]
        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: [:])

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 1)

        // Only positive-role stablecoins: USDC supply (20000)
        // DAI borrow excluded by isPositive filter, also filtered from weights (net < 0)
        // Weights total: BTC(50000) + USDC(20000) = 70000
        #expect(metrics.stablecoinRatio == Decimal(20000) / Decimal(70000))
    }

    @Test func `stablecoin ratio nets same-asset supply and borrow`() {
        let usdcAssetId = UUID()
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: nil,
                role: .balance,
                amount: 1,
                usdValue: 50000),
            TokenEntry(
                assetId: usdcAssetId,
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .supply,
                amount: 20000,
                usdValue: 20000),
            TokenEntry(
                assetId: usdcAssetId,
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: nil,
                role: .borrow,
                amount: 5000,
                usdValue: 5000)
        ]
        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: [:])

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 1)

        // USDC net = 20000 - 5000 = 15000, BTC = 50000, total = 65000
        #expect(metrics.stablecoinRatio == Decimal(15000) / Decimal(65000))
    }

    @Test func `stablecoin ratio consistent when all tokens have live prices`() throws {
        let tokens = [
            TokenEntry(
                assetId: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 1,
                usdValue: 50000),
            TokenEntry(
                assetId: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: "ethereum",
                role: .balance,
                amount: 10,
                usdValue: 25000),
            TokenEntry(
                assetId: UUID(),
                symbol: "USDC",
                name: "USD Coin",
                category: .stablecoin,
                coinGeckoId: "usd-coin",
                role: .balance,
                amount: 10000,
                usdValue: 10000)
        ]
        let prices: [String: Decimal] = try [
            "bitcoin": 55000,
            "ethereum": 3000,
            "usd-coin": #require(Decimal(string: "1.01"))
        ]
        let weights = PortfolioHealthFeature.computeAssetWeights(tokens: tokens, prices: prices)

        let metrics = PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokens, weights: weights, chainCount: 3)

        // Resolved: BTC=55000, ETH=30000, USDC=10100, total=95100
        #expect(metrics.stablecoinRatio == Decimal(10100) / Decimal(95100))
    }
}

// MARK: - B4: Risk Level Classification

struct PortfolioHealthRiskLevelTests {
    @Test func `high risk when HHI above 0_5`() throws {
        let metrics = try DiversificationMetrics(
            assetCount: 2,
            chainCount: 1,
            stablecoinRatio: 0,
            herfindahlIndex: #require(Decimal(string: "0.55")))

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .high)
    }

    @Test func `medium risk when HHI between 0_25 and 0_5`() throws {
        let metrics = try DiversificationMetrics(
            assetCount: 3,
            chainCount: 2,
            stablecoinRatio: #require(Decimal(string: "0.2")),
            herfindahlIndex: #require(Decimal(string: "0.38")))

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .medium)
    }

    @Test func `low risk when HHI at or below 0_25`() throws {
        let metrics = try DiversificationMetrics(
            assetCount: 5,
            chainCount: 3,
            stablecoinRatio: #require(Decimal(string: "0.3")),
            herfindahlIndex: #require(Decimal(string: "0.25")))

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .low)
    }

    @Test func `empty portfolio is low risk`() {
        let metrics = DiversificationMetrics(
            assetCount: 0,
            chainCount: 0,
            stablecoinRatio: 0,
            herfindahlIndex: 0)

        #expect(PortfolioHealthFeature.classifyRiskLevel(metrics: metrics) == .low)
    }
}
