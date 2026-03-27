import Foundation
import PortuCore

struct PositionTokenRowModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let positionID: UUID
    let symbol: String
    let assetName: String
    let accountName: String
    let chainLabel: String
    let role: TokenRole
    let displayAmount: Decimal
    let displayValue: Decimal

    var roleLabel: String {
        AssetValueFormatter.roleLabel(for: role)
    }
}
