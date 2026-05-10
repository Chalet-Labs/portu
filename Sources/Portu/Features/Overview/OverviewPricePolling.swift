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
            return pollingCoinGeckoID(
                token: token,
                prices: prices,
                override: override,
                settings: settings)
        }

        ids.append(contentsOf: watchlistIDs)
        return OverviewWatchlistStore.normalizedUniqueIDs(ids).sorted()
    }

    private static func pollingCoinGeckoID(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings) -> String? {
        let dashboardToken = TokenSettingsFeature.dashboardAdjustedToken(from: token, override: override)
        guard let coinGeckoId = dashboardToken.coinGeckoId else { return nil }

        if
            TokenSettingsFeature.isDashboardEligible(
                token: token,
                prices: prices,
                override: override,
                settings: settings) {
            return coinGeckoId
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
        return coinGeckoId
    }
}
