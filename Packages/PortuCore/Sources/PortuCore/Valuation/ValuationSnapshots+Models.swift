import Foundation
import SwiftData

// The model-to-snapshot boundary. The value types in this folder import Foundation only;
// reading SwiftData models happens here.

public extension TokenEntry {
    /// Convert active PositionTokens to TokenEntries, filtering out tokens without assets or inactive accounts.
    static func fromActiveTokens(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver = .defaults) -> [TokenEntry] {
        tokens.compactMap { token in
            guard let asset = token.asset, token.position?.account?.isActive == true else { return nil }
            return TokenEntry(
                assetId: asset.id, symbol: asset.symbol, name: asset.name,
                category: asset.category,
                portfolioCategory: categoryResolver.resolve(symbol: asset.symbol, legacyCategory: asset.category),
                coinGeckoId: asset.coinGeckoId,
                onchainIdentity: OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract),
                role: token.role, amount: token.amount, usdValue: token.usdValue,
                logoURL: asset.logoURL)
        }
    }
}

public extension TokenIdentityMappingSnapshot {
    @MainActor
    init(_ mapping: TokenIdentityMapping) {
        self.id = mapping.id
        self.canonicalKey = mapping.canonicalKey
        self.chain = mapping.chain
        self.contractAddress = mapping.contractAddress
        self.coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(mapping.coinGeckoId)
        self.zapperId = TokenIdentityMappingFeature.normalizedProviderID(mapping.zapperId)
    }
}

public extension TokenPricingOverrideSnapshot {
    @MainActor
    init(_ override: TokenPricingOverride) {
        self.init(
            id: override.id,
            assetId: override.assetId,
            manualPriceUSD: override.manualPriceUSD,
            coinGeckoIdOverride: override.coinGeckoIdOverride,
            isIgnored: override.isIgnored,
            alwaysShow: override.alwaysShow,
            notes: override.notes)
    }
}
