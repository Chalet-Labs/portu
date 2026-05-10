import Foundation
import SwiftData

@Model
public final class TokenPricingOverride {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var assetId: UUID
    public var manualPriceUSD: Decimal?
    public var coinGeckoIdOverride: String?
    public var isIgnored: Bool
    public var alwaysShow: Bool
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        assetId: UUID,
        manualPriceUSD: Decimal? = nil,
        coinGeckoIdOverride: String? = nil,
        isIgnored: Bool = false,
        alwaysShow: Bool = false,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now) {
        self.id = id
        self.assetId = assetId
        self.manualPriceUSD = manualPriceUSD
        self.coinGeckoIdOverride = coinGeckoIdOverride
        self.isIgnored = isIgnored
        self.alwaysShow = alwaysShow
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
