import Foundation
import SwiftData

/// Per-asset time-series snapshot that stores gross and borrow values separately.
@Model
public final class AssetSnapshot {
    public var id: UUID
    public var syncBatchId: UUID
    public var timestamp: Date
    public var accountId: UUID
    public var assetId: UUID
    public var symbol: String
    public var category: AssetCategory
    public var amount: Decimal
    public var usdValue: Decimal
    public var borrowAmount: Decimal
    public var borrowUsdValue: Decimal

    public init(
        syncBatchId: UUID,
        timestamp: Date,
        accountId: UUID,
        assetId: UUID,
        symbol: String,
        category: AssetCategory,
        amount: Decimal,
        usdValue: Decimal,
        borrowAmount: Decimal,
        borrowUsdValue: Decimal
    ) {
        self.id = UUID()
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.accountId = accountId
        self.assetId = assetId
        self.symbol = symbol
        self.category = category
        self.amount = amount
        self.usdValue = usdValue
        self.borrowAmount = borrowAmount
        self.borrowUsdValue = borrowUsdValue
    }
}
