import Foundation

struct PlatformTableRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let share: Decimal
    let networkCount: Int
    let positionCount: Int
    let usdBalance: Decimal
}
