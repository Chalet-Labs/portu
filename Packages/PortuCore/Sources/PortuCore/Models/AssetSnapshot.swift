import Foundation
import SwiftData

@Model
public final class AssetSnapshot: Timestamped {
    #Index<AssetSnapshot>([\.timestamp], [\.accountId, \.timestamp], [\.assetId, \.timestamp])

    @Attribute(.unique) public var id: UUID
    public var syncBatchId: UUID
    /// The hash modifier is what makes an existing store pick up the indexes above: SwiftData leaves
    /// the entity hash alone for an index-only change, so without it only new stores get them.
    @Attribute(hashModifier: "snapshot-time-series-indexes-1") public var timestamp: Date

    /// Not a relationship — survives deletion
    public var accountId: UUID
    public var assetId: UUID

    /// Denormalized asset metadata — survives Asset changes.
    public var symbol: String
    public var category: AssetCategory
    /// Legacy compatibility fields. Current portfolio category display is resolved
    /// from the live app-wide category rules at render time.
    public var portfolioCategoryID: String?
    public var portfolioCategoryName: String?

    /// GROSS POSITIVE: sum of supply + balance + stake + lpToken roles
    public var amount: Decimal
    public var usdValue: Decimal

    /// ABSOLUTE POSITIVE: borrow role tokens only, 0 if none
    public var borrowAmount: Decimal
    public var borrowUsdValue: Decimal

    public init(
        id: UUID = UUID(),
        syncBatchId: UUID,
        timestamp: Date,
        accountId: UUID,
        assetId: UUID,
        symbol: String,
        category: AssetCategory,
        portfolioCategoryID: String? = nil,
        portfolioCategoryName: String? = nil,
        amount: Decimal,
        usdValue: Decimal,
        borrowAmount: Decimal = 0,
        borrowUsdValue: Decimal = 0) {
        self.id = id
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.accountId = accountId
        self.assetId = assetId
        self.symbol = symbol
        self.category = category
        self.portfolioCategoryID = portfolioCategoryID
        self.portfolioCategoryName = portfolioCategoryName
        self.amount = amount
        self.usdValue = usdValue
        self.borrowAmount = borrowAmount
        self.borrowUsdValue = borrowUsdValue
    }
}
