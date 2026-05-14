import Foundation
import PortuCore

extension OverviewFeature {
    static func pricePollingIDs(
        tokens: [TokenEntry],
        prices: [String: Decimal] = [:],
        watchlistIDs: [String],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults) -> [String] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var ids = tokens.compactMap { token -> String? in
            let override = overrideMap[token.assetId]
            return pollingPriceID(
                token: token,
                prices: prices,
                override: override,
                settings: settings)
        }

        ids.append(contentsOf: watchlistIDs)
        return OverviewWatchlistStore.normalizedUniqueIDs(ids).sorted()
    }

    private static func pollingPriceID(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings) -> String? {
        guard
            let priceID = TokenSettingsFeature.resolvedPriceID(
                token: token,
                override: override)
        else { return nil }

        if
            TokenSettingsFeature.isDashboardEligible(
                token: token,
                prices: prices,
                override: override,
                settings: settings) {
            return priceID
        }

        guard token.amount > 0 else { return nil }
        guard token.role.isPositive || token.role.isBorrow else { return nil }
        guard override?.isIgnored != true else { return nil }
        guard
            TokenSettingsFeature.resolvedValue(
                token: token,
                prices: prices,
                override: override) == nil
        else { return nil }
        return priceID
    }
}
