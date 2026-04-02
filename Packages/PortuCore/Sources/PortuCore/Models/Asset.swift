import Foundation
import SwiftData

@Model
public final class Asset {
    @Attribute(.unique) public var id: UUID
    public var symbol: String
    public var name: String

    /// Tier 1 upsert key — cross-chain canonical identity
    public var coinGeckoId: String?

    // Tier 2 upsert key — single-chain token without coinGeckoId
    public var upsertChain: Chain?
    public var upsertContract: String?

    /// Tier 3 upsert key — provider-specific opaque ID
    public var sourceKey: String?

    /// Reserved for future DeBankProvider
    public var debankId: String?

    /// String, not URL — SwiftData predicate compatibility
    public var logoURL: String?

    public var category: AssetCategory
    public var isVerified: Bool

    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        coinGeckoId: String? = nil,
        upsertChain: Chain? = nil,
        upsertContract: String? = nil,
        sourceKey: String? = nil,
        debankId: String? = nil,
        logoURL: String? = nil,
        category: AssetCategory = .other,
        isVerified: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.coinGeckoId = coinGeckoId
        self.upsertChain = upsertChain
        self.upsertContract = upsertContract
        self.sourceKey = sourceKey
        self.debankId = debankId
        self.logoURL = logoURL
        self.category = category
        self.isVerified = isVerified
    }
}
