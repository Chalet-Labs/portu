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

    // Inverse of Portfolio.accounts — cascade delete rule means this Account
    // is deleted when its Portfolio is deleted.
    public var portfolio: Portfolio?

    public init(name: String, kind: AccountKind) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.holdings = []
    }
}
