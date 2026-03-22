import Foundation

struct AccountRowModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let groupName: String
    let secondaryLabel: String
    let searchIndex: String
    let typeLabel: String
    let usdBalance: Decimal
    let isActive: Bool
}
