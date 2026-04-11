import Foundation
import SwiftData

@Model
public final class AccountSnapshot: Timestamped {
    @Attribute(.unique) public var id: UUID
    public var syncBatchId: UUID
    public var timestamp: Date

    /// Not a relationship — survives account deletion for historical data
    public var accountId: UUID

    public var totalValue: Decimal

    /// true = synced successfully or manual account; false = remote sync failed
    public var isFresh: Bool

    public init(
        id: UUID = UUID(),
        syncBatchId: UUID,
        timestamp: Date,
        accountId: UUID,
        totalValue: Decimal,
        isFresh: Bool) {
        self.id = id
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.accountId = accountId
        self.totalValue = totalValue
        self.isFresh = isFresh
    }
}
