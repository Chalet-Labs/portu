import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Types

struct AssetWeight: Equatable, Identifiable {
    let symbol: String
    let name: String
    let usdValue: Decimal
    let percentage: Decimal

    var id: String {
        symbol + name
    }
}

struct ConcentrationRisk: Equatable, Identifiable {
    let symbol: String
    let name: String
    let percentage: Decimal
    let threshold: Decimal

    var id: String {
        symbol + name
    }
}

struct DiversificationMetrics: Equatable {
    let assetCount: Int
    let chainCount: Int
    let stablecoinRatio: Decimal
    let herfindahlIndex: Decimal
}

enum RiskLevel: Equatable {
    case low, medium, high
}

// MARK: - Reducer

@Reducer
struct PortfolioHealthFeature {
    @ObservableState
    struct State: Equatable {
        var showAllAssets: Bool = false
    }

    enum Action: Equatable {
        case showAllAssetsToggled
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showAllAssetsToggled:
                state.showAllAssets.toggle()
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// A group at or above this share of the portfolio raises a concentration warning.
    static let concentrationThreshold = Decimal(25) / 100

    static func computeConcentrationRisks(weights: [AssetWeight], threshold: Decimal) -> [ConcentrationRisk] {
        weights
            .filter { $0.percentage >= threshold }
            .map { ConcentrationRisk(symbol: $0.symbol, name: $0.name, percentage: $0.percentage, threshold: threshold) }
    }

    static func computeDiversificationMetrics(
        tokens: [TokenEntry], weights: [AssetWeight], chainCount: Int) -> DiversificationMetrics {
        let totalValue = weights.reduce(Decimal.zero) { $0 + $1.usdValue }

        let stablecoinIds = Set(tokens
            .filter { $0.portfolioCategory.semanticRole == .stablecoin }
            .map { $0.symbol + $0.name })
        let stablecoinValue = weights
            .filter { stablecoinIds.contains($0.id) }
            .reduce(Decimal.zero) { $0 + $1.usdValue }

        let stablecoinRatio = totalValue > 0 ? stablecoinValue / totalValue : 0
        let hhi = weights.reduce(Decimal.zero) { $0 + $1.percentage * $1.percentage }

        return DiversificationMetrics(
            assetCount: weights.count,
            chainCount: chainCount,
            stablecoinRatio: stablecoinRatio,
            herfindahlIndex: hhi)
    }

    static func classifyRiskLevel(metrics: DiversificationMetrics) -> RiskLevel {
        if metrics.herfindahlIndex > 0.5 {
            return .high
        }
        if metrics.herfindahlIndex > 0.25 {
            return .medium
        }
        return .low
    }
}
