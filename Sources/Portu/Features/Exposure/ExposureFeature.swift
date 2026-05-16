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

struct ExposureDashboardData: Equatable {
    let categoryRows: [CategoryExposure]
    let assetRows: [AssetExposure]
    let summary: ExposureSummary
    let pollingIDs: [String]
}

enum ExposureLabels {
    static let assetCountPillTitle = "Assets"
}

enum ExposureFeature {
    static func resolveTokenUSDValue(
        amount: Decimal,
        coinGeckoId: String?,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        resolveTokenUSDValue(
            amount: amount,
            priceID: TokenIdentityMappingFeature.normalizedProviderID(coinGeckoId),
            usdValue: usdValue,
            prices: prices)
    }

    static func resolveTokenUSDValue(
        amount: Decimal,
        priceID: String?,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        if let priceID, let livePrice = prices[priceID] {
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
                amount: token.amount,
                priceID: TokenSettingsFeature.resolvedPriceID(token: token, override: nil),
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
                amount: token.amount,
                priceID: TokenSettingsFeature.resolvedPriceID(token: token, override: nil),
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

    static func computeDashboardData(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults) -> ExposureDashboardData {
        computeDashboardData(
            tokens: tokens,
            prices: prices,
            overrideMap: TokenSettingsFeature.overridesByAssetId(overrides),
            settings: settings)
    }

    static func computeDashboardData(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrideMap: [UUID: TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults) -> ExposureDashboardData {
        var categoryBuckets: [PortfolioCategorySnapshot: (assets: Decimal, borrows: Decimal)] = [:]
        var assetMap: [UUID: AssetAggregate] = [:]
        var pollingIDs: Set<String> = []

        for token in tokens {
            let override = overrideMap[token.assetId]
            let dashboardToken = TokenSettingsFeature.dashboardAdjustedToken(from: token, override: override)
            if
                let priceID = dashboardPollingPriceID(
                    token: token,
                    prices: prices,
                    override: override,
                    settings: settings) {
                pollingIDs.insert(priceID)
            }

            guard
                TokenSettingsFeature.isDashboardEligible(
                    token: token,
                    prices: prices,
                    override: override,
                    settings: settings)
            else { continue }

            let value = dashboardResolvedValue(
                token: token,
                dashboardToken: dashboardToken,
                prices: prices,
                override: override)

            var categoryEntry = categoryBuckets[dashboardToken.portfolioCategory] ?? (0, 0)
            var assetEntry = assetMap[dashboardToken.assetId] ?? AssetAggregate(
                symbol: dashboardToken.symbol,
                category: dashboardToken.category,
                portfolioCategory: dashboardToken.portfolioCategory,
                logoURL: dashboardToken.logoURL,
                assets: 0,
                borrows: 0)
            assetEntry.logoURL = assetEntry.logoURL ?? dashboardToken.logoURL

            if dashboardToken.role.isPositive {
                categoryEntry.assets += value
                assetEntry.assets += value
            } else if dashboardToken.role.isBorrow {
                categoryEntry.borrows += value
                assetEntry.borrows += value
            }

            categoryBuckets[dashboardToken.portfolioCategory] = categoryEntry
            assetMap[dashboardToken.assetId] = assetEntry
        }

        let totalSpot = categoryBuckets.values.reduce(Decimal.zero) { $0 + $1.assets }
        let categoryRows = categoryBuckets.compactMap { bucket, exposure in
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

        let assetRows = assetMap.map { id, entry in
            AssetExposure(
                id: id,
                symbol: entry.symbol,
                category: entry.category,
                portfolioCategory: entry.portfolioCategory,
                spotAssets: entry.assets,
                liabilities: entry.borrows,
                logoURL: entry.logoURL,
                shareOfSpot: shareOfSpot(netExposure: entry.assets - entry.borrows, totalSpot: totalSpot))
        }
        .sorted(by: sortAssetRows)

        let summary = computeSummary(from: categoryRows)
        return ExposureDashboardData(
            categoryRows: categoryRows,
            assetRows: assetRows,
            summary: summary,
            pollingIDs: Array(pollingIDs).sorted())
    }

    private static func dashboardResolvedValue(
        token: TokenEntry,
        dashboardToken: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        TokenSettingsFeature.resolvedValue(token: token, prices: prices, override: override)
            ?? dashboardToken.usdValue
    }

    private static func dashboardPollingPriceID(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings) -> String? {
        guard token.amount > 0 else { return nil }
        guard token.role.isPositive || token.role.isBorrow else { return nil }
        guard let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override) else { return nil }

        if
            TokenSettingsFeature.isDashboardEligible(
                token: token,
                prices: prices,
                override: override,
                settings: settings) {
            return priceID
        }

        guard override?.isIgnored != true else { return nil }
        guard
            TokenSettingsFeature.resolvedValue(
                token: token,
                prices: prices,
                override: override) == nil
        else { return nil }

        return priceID
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
        pricePollingIDs(
            tokens: tokens,
            overrideMap: TokenSettingsFeature.overridesByAssetId(overrides))
    }

    static func pricePollingIDs(
        tokens: [TokenEntry],
        overrideMap: [UUID: TokenPricingOverrideSnapshot]) -> [String] {
        let ids = tokens.compactMap { token -> String? in
            guard token.amount > 0, token.role.isPositive || token.role.isBorrow else { return nil }
            return TokenSettingsFeature.resolvedPriceID(
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
