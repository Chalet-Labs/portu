import Foundation
import SwiftData

@Model
public final class Holding {
    public var id: UUID
    public var amount: Decimal
    public var costBasis: Decimal?

    // Back-reference — nullify (set to nil when Account is deleted via cascade).
    // @Relationship is on the Account side.
    public var account: Account?

    // Many-to-one with Asset. @Relationship on this side because Asset.holdings
    // is the inverse. nullify = optional.
    @Relationship(deleteRule: .nullify, inverse: \Asset.holdings)
    public var asset: Asset?

    public init(amount: Decimal, costBasis: Decimal? = nil) {
        self.id = UUID()
        self.amount = amount
        self.costBasis = costBasis
    }
}
