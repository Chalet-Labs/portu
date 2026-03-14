import Foundation
import SwiftData

@Model
public final class Portfolio {
    public var id: UUID
    public var name: String
    @Relationship(deleteRule: .cascade, inverse: \Account.portfolio)
    public var accounts: [Account]
    public var createdAt: Date

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.accounts = []
        self.createdAt = .now
    }
}
