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

    static func computeAssetWeights(tokens: [TokenEntry], prices: [String: Decimal]) -> [AssetWeight] {
        // Group by (symbol, name), net positive - borrow, skip rewards
        var groups: [String: (symbol: String, name: String, value: Decimal)] = [:]

        for token in tokens {
            let resolved = resolveValue(token: token, prices: prices)
            let key = token.symbol + token.name

            var entry = groups[key] ?? (symbol: token.symbol, name: token.name, value: 0)
            if token.role.isPositive {
                entry.value += resolved
            } else if token.role.isBorrow {
                entry.value -= resolved
            }
            groups[key] = entry
        }

        let total = groups.values.reduce(Decimal.zero) { $0 + max(0, $1.value) }
        guard total > 0 else { return [] }

        return groups.values
            .filter { $0.value > 0 }
            .map { AssetWeight(symbol: $0.symbol, name: $0.name, usdValue: $0.value, percentage: $0.value / total) }
            .sorted { $0.percentage > $1.percentage }
    }

    static func computeConcentrationRisks(weights: [AssetWeight], threshold: Decimal) -> [ConcentrationRisk] {
        weights
            .filter { $0.percentage >= threshold }
            .map { ConcentrationRisk(symbol: $0.symbol, name: $0.name, percentage: $0.percentage, threshold: threshold) }
    }

    static func computeDiversificationMetrics(
        tokens: [TokenEntry], weights: [AssetWeight], chainCount: Int, prices: [String: Decimal]) -> DiversificationMetrics {
        let totalValue = weights.reduce(Decimal.zero) { $0 + $1.usdValue }

        let stablecoinValue = tokens
            .filter { $0.category == .stablecoin && $0.role.isPositive }
            .reduce(Decimal.zero) { $0 + resolveValue(token: $1, prices: prices) }

        let stablecoinRatio = totalValue > 0 ? stablecoinValue / totalValue : 0
        let hhi = weights.reduce(Decimal.zero) { $0 + $1.percentage * $1.percentage }

        return DiversificationMetrics(
            assetCount: weights.count,
            chainCount: chainCount,
            stablecoinRatio: stablecoinRatio,
            herfindahlIndex: hhi)
    }

    static func classifyRiskLevel(metrics: DiversificationMetrics) -> RiskLevel {
        if metrics.herfindahlIndex > Decimal(string: "0.5")! { return .high }
        if metrics.herfindahlIndex > Decimal(string: "0.25")! { return .medium }
        return .low
    }

    // MARK: - Private

    private static func resolveValue(token: TokenEntry, prices: [String: Decimal]) -> Decimal {
        if let cgId = token.coinGeckoId, let livePrice = prices[cgId] {
            return token.amount * livePrice
        }
        return token.usdValue
    }
}
