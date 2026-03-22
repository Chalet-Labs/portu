import Foundation
import SwiftData

/// Shared asset reference data used by many position tokens.
@Model
public final class Asset {
    public var id: UUID
    public var symbol: String
    public var name: String
    public var coinGeckoId: String?
    public var upsertChain: Chain?
    public var upsertContract: String?
    public var sourceKey: String?
    public var debankId: String?
    public var logoURL: String?
    public var category: AssetCategory
    public var isVerified: Bool

    public var positionTokens: [PositionToken]

    public init(
        symbol: String,
        name: String,
        coinGeckoId: String? = nil,
        upsertChain: Chain? = nil,
        upsertContract: String? = nil,
        sourceKey: String? = nil,
        debankId: String? = nil,
        logoURL: String? = nil,
        category: AssetCategory = .other,
        isVerified: Bool = false
    ) {
        self.id = UUID()
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
        self.positionTokens = []
    }
}
