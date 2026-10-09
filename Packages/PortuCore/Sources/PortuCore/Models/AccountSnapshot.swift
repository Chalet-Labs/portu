import Foundation
import SwiftData

@Model
public final class AccountSnapshot {
    #Index<AccountSnapshot>([\.timestamp], [\.accountId, \.timestamp])

    @Attribute(.unique) public var id: UUID
    public var syncBatchId: UUID
    /// The hash modifier is what makes an existing store pick up the indexes above: SwiftData leaves
    /// the entity hash alone for an index-only change, so without it only new stores get them.
    @Attribute(hashModifier: "snapshot-time-series-indexes-1") public var timestamp: Date

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
