import Foundation
import SwiftData

/// Stub: will be fleshed out in a later task.
@Model
public final class Portfolio {
    public var id: UUID
    public var name: String
    public var accounts: [Account]

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.accounts = []
    }
}
