import Foundation
import SwiftData

@Model
public final class PositionToken {
    @Attribute(.unique) public var id: UUID

    public var role: TokenRole

    /// ALWAYS POSITIVE — role provides the sign
    public var amount: Decimal

    /// ALWAYS POSITIVE — role provides the sign
    public var usdValue: Decimal

    /// N:1 — assets are shared reference data (nullify on delete)
    public var asset: Asset?

    public var position: Position?

    public init(
        id: UUID = UUID(),
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        asset: Asset? = nil,
        position: Position? = nil) {
        self.id = id
        self.role = role
        self.amount = amount
        self.usdValue = usdValue
        self.asset = asset
        self.position = position
    }

    /// Resolve USD value using live price when available, falling back to stored value.
    public func resolvedUSDValue(prices: [String: Decimal]) -> Decimal {
        asset?.coinGeckoId.flatMap { prices[$0] }.map { amount * $0 } ?? usdValue
    }
}
