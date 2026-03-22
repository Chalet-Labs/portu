import Foundation
import SwiftData

/// Stub: will be replaced by PositionToken in a later task.
@Model
public final class Holding {
    public var id: UUID
    public var account: Account?
    public var asset: Asset?

    public init() {
        self.id = UUID()
    }
}
