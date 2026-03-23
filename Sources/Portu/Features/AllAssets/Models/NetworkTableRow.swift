import Foundation

struct NetworkTableRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let share: Decimal
    let positionCount: Int
    let usdBalance: Decimal
}
