import Foundation

public struct TokenPricingOverrideSnapshot: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var assetId: UUID
    public var manualPriceUSD: Decimal?
    public var coinGeckoIdOverride: String?
    public var isIgnored: Bool
    public var alwaysShow: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        assetId: UUID,
        manualPriceUSD: Decimal? = nil,
        coinGeckoIdOverride: String? = nil,
        isIgnored: Bool = false,
        alwaysShow: Bool = false,
        notes: String = "") {
        self.id = id
        self.assetId = assetId
        self.manualPriceUSD = manualPriceUSD
        self.coinGeckoIdOverride = coinGeckoIdOverride
        self.isIgnored = isIgnored
        self.alwaysShow = alwaysShow
        self.notes = notes
    }
}
