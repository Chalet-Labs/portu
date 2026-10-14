import Foundation
import SwiftData

// The model-to-snapshot boundary. The value types in this folder import Foundation only;
// reading SwiftData models happens here.

public extension TokenEntry {
    /// Projects a position token. Callers choose the category and CoinGecko ID, since screens
    /// resolve those differently today.
    init(
        _ token: PositionToken,
        asset: Asset,
        portfolioCategory: PortfolioCategorySnapshot,
        coinGeckoId: String?) {
        self.init(
            assetId: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            category: asset.category,
            portfolioCategory: portfolioCategory,
            coinGeckoId: coinGeckoId,
            onchainIdentity: OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract),
            role: token.role,
            amount: token.amount,
            usdValue: token.usdValue,
            logoURL: asset.logoURL,
            syncedAt: token.position?.syncedAt)
    }
}

public extension TokenIdentityMappingSnapshot {
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

public extension PositionContext {
    init(_ position: Position) {
        self.init(
            positionId: position.id,
            positionType: position.positionType,
            accountId: position.account?.id,
            chain: position.chain,
            protocolId: position.protocolId)
    }
}

public extension ValuationInput {
    /// Projects a position token, or `nil` when it has no asset or no position: such tokens are
    /// outside valuation everywhere.
    init?(_ token: PositionToken, categoryResolver: PortfolioCategoryResolver = .defaults) {
        guard let asset = token.asset, let position = token.position else { return nil }
        self.init(
            tokenId: token.id,
            token: TokenEntry(
                token,
                asset: asset,
                portfolioCategory: categoryResolver.resolve(symbol: asset.symbol, legacyCategory: asset.category),
                coinGeckoId: asset.coinGeckoId),
            position: PositionContext(position))
    }

    /// The dashboard input: tokens of active accounts only.
    static func activeAccounts(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver = .defaults) -> [ValuationInput] {
        tokens.compactMap { token in
            guard token.position?.account?.isActive == true else { return nil }
            return ValuationInput(token, categoryResolver: categoryResolver)
        }
    }

    /// The Accounts input (S9): every account, active or not.
    static func allAccounts(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver = .defaults) -> [ValuationInput] {
        tokens.compactMap { ValuationInput($0, categoryResolver: categoryResolver) }
    }
}

public extension HistoricalCloseRow {
    init(_ point: HistoricalPricePoint) {
        self.init(priceID: point.coinGeckoId, day: point.day, currency: point.fiatCurrency, price: point.price)
    }
}
