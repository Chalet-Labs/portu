import Foundation

enum AssetChartMode: String, CaseIterable, Identifiable, Sendable {
    case price = "Price"
    case value = "$ Value"
    case amount = "Amount"

    var id: String { rawValue }
    var title: String { rawValue }
}
