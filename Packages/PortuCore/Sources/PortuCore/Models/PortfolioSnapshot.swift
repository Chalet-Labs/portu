import Foundation
import SwiftData

/// Portfolio-wide time-series snapshot for performance history.
@Model
public final class PortfolioSnapshot {
    public var id: UUID
    public var syncBatchId: UUID
    public var timestamp: Date
    public var totalValue: Decimal
    public var idleValue: Decimal
    public var deployedValue: Decimal
    public var debtValue: Decimal
    public var isPartial: Bool

    public init(
        syncBatchId: UUID,
        timestamp: Date,
        totalValue: Decimal,
        idleValue: Decimal,
        deployedValue: Decimal,
        debtValue: Decimal,
        isPartial: Bool
    ) {
        self.id = UUID()
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.totalValue = totalValue
        self.idleValue = idleValue
        self.deployedValue = deployedValue
        self.debtValue = debtValue
        self.isPartial = isPartial
    }
}
