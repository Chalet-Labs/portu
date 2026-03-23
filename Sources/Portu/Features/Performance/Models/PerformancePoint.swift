import Foundation

struct PerformancePoint: Identifiable, Equatable, Sendable {
    let id: Date
    let date: Date
    let value: Decimal
    let usesAccountSnapshot: Bool

    init(
        date: Date,
        value: Decimal,
        usesAccountSnapshot: Bool
    ) {
        self.id = date
        self.date = date
        self.value = value
        self.usesAccountSnapshot = usesAccountSnapshot
    }
}
