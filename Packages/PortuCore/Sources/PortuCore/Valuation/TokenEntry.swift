import Foundation

/// Lightweight input for row aggregation — decouples from SwiftData models.
public struct TokenEntry: Equatable, Sendable {
    public let assetId: UUID
    public let symbol: String
    public let name: String
    public let category: AssetCategory
    public let portfolioCategory: PortfolioCategorySnapshot
    public let coinGeckoId: String?
    public let onchainIdentity: OnchainTokenIdentity?
    public let role: TokenRole
    public let amount: Decimal
    public let usdValue: Decimal
    public let logoURL: String?
    /// When the position holding this token was last synced; `nil` when the entry has no position.
    public let syncedAt: Date?

    public init(
        assetId: UUID,
        symbol: String,
        name: String,
        category: AssetCategory,
        portfolioCategory: PortfolioCategorySnapshot? = nil,
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity? = nil,
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        logoURL: String? = nil,
        syncedAt: Date? = nil) {
        self.assetId = assetId
        self.symbol = symbol
        self.name = name
        self.category = category
        self.portfolioCategory = portfolioCategory
            ?? PortfolioCategoryResolver.defaults.resolve(symbol: symbol, legacyCategory: category)
        self.coinGeckoId = coinGeckoId
        self.onchainIdentity = onchainIdentity
        self.role = role
        self.amount = amount
        self.usdValue = usdValue
        self.logoURL = logoURL
        self.syncedAt = syncedAt
    }
}
