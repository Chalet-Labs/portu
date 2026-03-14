import Foundation
import SwiftData

@Model
public final class Account {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var exchangeType: ExchangeType?
    public var chain: Chain?
    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    public var holdings: [Holding]
    public var lastSyncedAt: Date?

    // Back-reference — nullify delete rule (set to nil when Portfolio is deleted).
    // @Relationship is on the Portfolio side; this is the inverse target.
    public var portfolio: Portfolio?

    public init(name: String, kind: AccountKind) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.holdings = []
    }
}
