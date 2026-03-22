import Foundation
import SwiftData

/// Per-account time-series snapshot that survives account deletion.
@Model
public final class AccountSnapshot {
    public var id: UUID
    public var syncBatchId: UUID
    public var timestamp: Date
    public var accountId: UUID
    public var totalValue: Decimal
    public var isFresh: Bool

    public init(
        syncBatchId: UUID,
        timestamp: Date,
        accountId: UUID,
        totalValue: Decimal,
        isFresh: Bool
    ) {
        self.id = UUID()
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.accountId = accountId
        self.totalValue = totalValue
        self.isFresh = isFresh
    }
}
