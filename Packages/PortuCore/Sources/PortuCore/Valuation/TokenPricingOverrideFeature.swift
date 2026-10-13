import Foundation

/// The pure override layer: which override applies to an asset, and which CoinGecko ID and price ID
/// a token resolves to once overrides and identity mappings are applied (spec I3).
public enum TokenPricingOverrideFeature {
    /// One override per asset. Duplicates keep the lowest override ID so the choice never depends on
    /// fetch order.
    public static func overridesByAssetId(
        _ overrides: [TokenPricingOverrideSnapshot]) -> [UUID: TokenPricingOverrideSnapshot] {
        Dictionary(overrides.map { ($0.assetId, $0) }, uniquingKeysWith: { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
        })
    }

    /// The assets whose applying override (see `overridesByAssetId`) ignores them.
    public static func ignoredAssetIds(_ overrides: [TokenPricingOverrideSnapshot]) -> Set<UUID> {
        Set(overridesByAssetId(overrides).values.filter(\.isIgnored).map(\.assetId))
    }

    /// A manual price counts only when it is positive.
    public static func sanitizedManualPrice(_ price: Decimal?) -> Decimal? {
        guard let price, price > 0 else { return nil }
        return price
    }

    /// The override CoinGecko ID, else the asset's, else the identity-mapped one, each normalized.
    public static func resolvedCoinGeckoID(
        token: TokenEntry,
        override: TokenPricingOverrideSnapshot?,
        mappingsByIdentity: [OnchainTokenIdentity: TokenIdentityMappingSnapshot] = [:]) -> String? {
        TokenIdentityMappingFeature.normalizedProviderID(override?.coinGeckoIdOverride)
            ?? TokenIdentityMappingFeature.normalizedProviderID(token.coinGeckoId)
            ?? TokenIdentityMappingFeature.mappedCoinGeckoID(
                for: token.onchainIdentity,
                mappingsByIdentity: mappingsByIdentity)
    }

    /// The ID the token is priced under, or `nil` when a manual price makes it irrelevant.
    public static func resolvedPriceID(
        token: TokenEntry,
        override: TokenPricingOverrideSnapshot?,
        mappingsByIdentity: [OnchainTokenIdentity: TokenIdentityMappingSnapshot] = [:]) -> String? {
        if sanitizedManualPrice(override?.manualPriceUSD) != nil {
            return nil
        }
        return marketPriceID(token: token, override: override, mappingsByIdentity: mappingsByIdentity)
    }

    /// The ID the market quotes the token under, whatever its manual price: a manual price changes
    /// the value, not the coin.
    public static func marketPriceID(
        token: TokenEntry,
        override: TokenPricingOverrideSnapshot?,
        mappingsByIdentity: [OnchainTokenIdentity: TokenIdentityMappingSnapshot] = [:]) -> String? {
        TokenIdentityMappingFeature.priceID(
            coinGeckoId: resolvedCoinGeckoID(token: token, override: override, mappingsByIdentity: mappingsByIdentity),
            onchainIdentity: token.onchainIdentity)
    }
}
