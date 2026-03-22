import Foundation
import SwiftData

/// A token that participates in a position with sign semantics carried by its role.
@Model
public final class PositionToken {
    public var id: UUID
    public var role: TokenRole
    public var amount: Decimal
    public var usdValue: Decimal

    public var asset: Asset?

    public var position: Position?

    public init(
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        asset: Asset? = nil,
        position: Position? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.amount = amount
        self.usdValue = usdValue
        self.asset = asset
        self.position = position
    }
}
