import Foundation
import PortuCore

struct AssetTableRow: Identifiable, Equatable, Sendable {
    let id: String
    let assetID: UUID?
    let symbol: String
    let name: String
    let category: AssetCategory
    let netAmount: Decimal
    let grossValue: Decimal
    let price: Decimal
    let value: Decimal
    let priceSource: AssetValueFormatter.PriceSource?
    let accountGroups: [String]
    let searchIndex: String
}
