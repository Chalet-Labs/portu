import Foundation

struct PositionSectionModel: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let protocolName: String?
    let chainLabel: String?
    let healthFactor: Double?
    let value: Decimal
    let rows: [PositionTokenRowModel]
    let children: [PositionSectionModel]
}
