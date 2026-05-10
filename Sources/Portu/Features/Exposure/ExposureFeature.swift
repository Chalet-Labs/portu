import Foundation
import PortuCore

protocol ExposureRow: Identifiable, Equatable {
    var spotAssets: Decimal { get }
    var liabilities: Decimal { get }
    var shareOfSpot: Decimal { get }
}

extension ExposureRow {
    var netExposure: Decimal {
        spotAssets - liabilities
    }
}

nonisolated struct CategoryExposure: ExposureRow {
    let id: String
    let name: String
    let semanticRole: PortfolioCategorySemanticRole
    let spotAssets: Decimal
    let liabilities: Decimal
    let shareOfSpot: Decimal

    init(
        id: String,
        name: String,
        semanticRole: PortfolioCategorySemanticRole = .normal,
        spotAssets: Decimal,
        liabilities: Decimal,
        shareOfSpot: Decimal = 0) {
        self.id = id
        self.name = name
        self.semanticRole = semanticRole
        self.spotAssets = spotAssets
        self.liabilities = liabilities
        self.shareOfSpot = shareOfSpot
    }
}

nonisolated struct AssetExposure: ExposureRow {
    let id: UUID
    let symbol: String
    let category: AssetCategory
    let portfolioCategory: PortfolioCategorySnapshot
    let spotAssets: Decimal
    let liabilities: Decimal
    let logoURL: String?
    let shareOfSpot: Decimal

    init(
        id: UUID,
        symbol: String,
        category: AssetCategory,
        portfolioCategory: PortfolioCategorySnapshot,
        spotAssets: Decimal,
        liabilities: Decimal,
        logoURL: String? = nil,
        shareOfSpot: Decimal = 0) {
        self.id = id
        self.symbol = symbol
        self.category = category
        self.portfolioCategory = portfolioCategory
        self.spotAssets = spotAssets
        self.liabilities = liabilities
        self.logoURL = logoURL
        self.shareOfSpot = shareOfSpot
    }
}

struct ExposureSummary: Equatable {
    let totalSpot: Decimal
    let totalLiabilities: Decimal
    let netExposure: Decimal
}

enum ExposureFeature {
    static func resolveTokenUSDValue(
        amount: Decimal,
        coinGeckoId: String?,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        if let cgId = coinGeckoId, let livePrice = prices[cgId] {
            return amount * livePrice
        }
        return usdValue
    }

    static func computeCategoryExposure(
        tokens: [TokenEntry],
        prices: [String: Decimal]) -> [CategoryExposure] {
        var buckets: [PortfolioCategorySnapshot: (assets: Decimal, borrows: Decimal)] = [:]

        for token in tokens {
            if token.role.isReward { continue }
            let value = resolveTokenUSDValue(
                amount: token.amount, coinGeckoId: token.coinGeckoId,
                usdValue: token.usdValue, prices: prices)
            let bucket = token.portfolioCategory
            var entry = buckets[bucket] ?? (0, 0)
            if token.role.isPositive {
                entry.assets += value
            } else if token.role.isBorrow {
                entry.borrows += value
            }
            buckets[bucket] = entry
        }

        let totalSpot = buckets.values.reduce(Decimal.zero) { $0 + $1.assets }
        return buckets.compactMap { bucket, exposure in
            guard exposure.assets > 0 || exposure.borrows > 0 else { return nil }
            return CategoryExposure(
                id: bucket.id.uuidString,
                name: bucket.name,
                semanticRole: bucket.semanticRole,
                spotAssets: exposure.assets,
                liabilities: exposure.borrows,
                shareOfSpot: shareOfSpot(netExposure: exposure.assets - exposure.borrows, totalSpot: totalSpot))
        }
        .sorted(by: sortExposureRows)
    }

    private struct AssetAggregate {
        let symbol: String
        let category: AssetCategory
        let portfolioCategory: PortfolioCategorySnapshot
        var logoURL: String?
        var assets: Decimal
        var borrows: Decimal
    }

    static func computeAssetExposure(
        tokens: [TokenEntry],
        prices: [String: Decimal]) -> [AssetExposure] {
        var assetMap: [UUID: AssetAggregate] = [:]

        for token in tokens {
            if token.role.isReward { continue }
            let value = resolveTokenUSDValue(
                amount: token.amount, coinGeckoId: token.coinGeckoId,
                usdValue: token.usdValue, prices: prices)
            var entry = assetMap[token.assetId] ?? AssetAggregate(
                symbol: token.symbol,
                category: token.category,
                portfolioCategory: token.portfolioCategory,
                logoURL: token.logoURL,
                assets: 0,
                borrows: 0)
            entry.logoURL = entry.logoURL ?? token.logoURL
            if token.role.isPositive {
                entry.assets += value
            } else if token.role.isBorrow {
                entry.borrows += value
            }
            assetMap[token.assetId] = entry
        }

        let totalSpot = assetMap.values.reduce(Decimal.zero) { $0 + $1.assets }
        return assetMap.map { id, entry in
            AssetExposure(
                id: id, symbol: entry.symbol, category: entry.category,
                portfolioCategory: entry.portfolioCategory,
                spotAssets: entry.assets, liabilities: entry.borrows,
                logoURL: entry.logoURL,
                shareOfSpot: shareOfSpot(netExposure: entry.assets - entry.borrows, totalSpot: totalSpot))
        }
        .sorted(by: sortAssetRows)
    }

    static func computeDashboardAssetExposure(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults) -> [AssetExposure] {
        computeAssetExposure(
            tokens: TokenSettingsFeature.dashboardEligibleTokens(
                tokens: tokens,
                prices: prices,
                overrides: overrides,
                settings: settings),
            prices: prices)
    }

    static func computeSummary(from categories: [CategoryExposure]) -> ExposureSummary {
        ExposureSummary(
            totalSpot: categories.reduce(0) { $0 + $1.spotAssets },
            totalLiabilities: categories.reduce(0) { $0 + $1.liabilities },
            netExposure: categories
                .filter { $0.semanticRole != .stablecoin }
                .reduce(0) { $0 + $1.netExposure })
    }

    static func pricePollingIDs(
        tokens: [TokenEntry],
        overrides: [TokenPricingOverrideSnapshot]) -> [String] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        let ids = tokens.compactMap { token -> String? in
            guard token.amount > 0, token.role.isPositive || token.role.isBorrow else { return nil }
            return TokenSettingsFeature.resolvedCoinGeckoID(
                token: token,
                override: overrideMap[token.assetId])
        }

        return Array(Set(ids)).sorted()
    }

    private static func shareOfSpot(netExposure: Decimal, totalSpot: Decimal) -> Decimal {
        guard totalSpot > 0 else { return 0 }
        return netExposure / totalSpot
    }

    private static func sortExposureRows(_ lhs: CategoryExposure, _ rhs: CategoryExposure) -> Bool {
        if lhs.netExposure == rhs.netExposure {
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }
        return lhs.netExposure > rhs.netExposure
    }

    private static func sortAssetRows(_ lhs: AssetExposure, _ rhs: AssetExposure) -> Bool {
        if lhs.netExposure == rhs.netExposure {
            let symbolOrder = lhs.symbol.localizedStandardCompare(rhs.symbol)
            if symbolOrder != .orderedSame {
                return symbolOrder == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.netExposure > rhs.netExposure
    }
}
