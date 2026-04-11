import Foundation
import SwiftData

@Model
public final class PortfolioSnapshot: Timestamped {
    @Attribute(.unique) public var id: UUID
    public var syncBatchId: UUID
    public var timestamp: Date
    public var totalValue: Decimal
    public var idleValue: Decimal
    public var deployedValue: Decimal
    public var debtValue: Decimal

    /// true if any account failed during this sync batch
    public var isPartial: Bool

    public init(
        id: UUID = UUID(),
        syncBatchId: UUID,
        timestamp: Date,
        totalValue: Decimal,
        idleValue: Decimal,
        deployedValue: Decimal,
        debtValue: Decimal,
        isPartial: Bool) {
        self.id = id
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.totalValue = totalValue
        self.idleValue = idleValue
        self.deployedValue = deployedValue
        self.debtValue = debtValue
        self.isPartial = isPartial
    }
}
