import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

/// Category-level exposure breakdown.
nonisolated struct CategoryExposure: Identifiable, Equatable {
    let id: String
    let name: String
    let spotAssets: Decimal
    let liabilities: Decimal
    var spotNet: Decimal {
        spotAssets - liabilities
    }

    var netExposure: Decimal {
        spotNet
    }
}

/// Asset-level exposure breakdown.
nonisolated struct AssetExposure: Identifiable, Equatable {
    let id: UUID
    let symbol: String
    let category: AssetCategory
    let spotAssets: Decimal
    let liabilities: Decimal
    var spotNet: Decimal {
        spotAssets - liabilities
    }

    var netExposure: Decimal {
        spotNet
    }
}

/// Summary totals for the exposure dashboard.
struct ExposureSummary: Equatable {
    let totalSpot: Decimal
    let totalLiabilities: Decimal
    let netExposure: Decimal
}

// MARK: - ExposureFeature

@Reducer
struct ExposureFeature {
    @ObservableState
    struct State: Equatable {
        var showByAsset: Bool = false
    }

    enum Action: Equatable {
        case viewModeChanged(Bool)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .viewModeChanged(byAsset):
                state.showByAsset = byAsset
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Resolve USD value for a token using live price or fallback.
    static func resolveTokenUSDValue(
        amount: Decimal,
        coinGeckoId: String?,
        usdValue: Decimal,
        prices: [String: Decimal],
    ) -> Decimal {
        if let cgId = coinGeckoId, let livePrice = prices[cgId] {
            return amount * livePrice
        }
        return usdValue
    }

    /// Aggregate token entries into category-level exposure.
    static func computeCategoryExposure(
        tokens: [TokenEntry],
        prices: [String: Decimal],
    ) -> [CategoryExposure] {
        var assets: [AssetCategory: Decimal] = [:]
        var borrows: [AssetCategory: Decimal] = [:]

        for token in tokens {
            if token.role.isReward { continue }
            let value = resolveTokenUSDValue(
                amount: token.amount, coinGeckoId: token.coinGeckoId,
                usdValue: token.usdValue, prices: prices,
            )
            if token.role.isPositive {
                assets[token.category, default: 0] += value
            } else if token.role.isBorrow {
                borrows[token.category, default: 0] += value
            }
        }

        return AssetCategory.allCases.compactMap { cat in
            let a = assets[cat, default: 0]
            let b = borrows[cat, default: 0]
            guard a > 0 || b > 0 else { return nil }
            return CategoryExposure(
                id: cat.rawValue,
                name: cat.rawValue.capitalized,
                spotAssets: a,
                liabilities: b,
            )
        }
    }

    /// Aggregate token entries into asset-level exposure.
    static func computeAssetExposure(
        tokens: [TokenEntry],
        prices: [String: Decimal],
    ) -> [AssetExposure] {
        var assetMap: [UUID: (symbol: String, category: AssetCategory,
                              assets: Decimal, borrows: Decimal)] = [:]

        for token in tokens {
            if token.role.isReward { continue }
            let value = resolveTokenUSDValue(
                amount: token.amount, coinGeckoId: token.coinGeckoId,
                usdValue: token.usdValue, prices: prices,
            )
            var entry = assetMap[token.assetId] ?? (token.symbol, token.category, 0, 0)
            if token.role.isPositive {
                entry.assets += value
            } else if token.role.isBorrow {
                entry.borrows += value
            }
            assetMap[token.assetId] = entry
        }

        return assetMap.map { id, entry in
            AssetExposure(
                id: id, symbol: entry.symbol, category: entry.category,
                spotAssets: entry.assets, liabilities: entry.borrows,
            )
        }
        .sorted { $0.spotNet > $1.spotNet }
    }

    /// Compute summary totals from category exposures.
    static func computeSummary(from categories: [CategoryExposure]) -> ExposureSummary {
        ExposureSummary(
            totalSpot: categories.reduce(0) { $0 + $1.spotAssets },
            totalLiabilities: categories.reduce(0) { $0 + $1.liabilities },
            netExposure: categories
                .filter { $0.id != AssetCategory.stablecoin.rawValue }
                .reduce(0) { $0 + $1.spotNet },
        )
    }
}
