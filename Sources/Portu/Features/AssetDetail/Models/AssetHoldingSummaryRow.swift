import Foundation

struct AssetHoldingSummaryRow: Identifiable, Equatable, Sendable {
    let id: String
    let networkName: String
    let amount: Decimal
    let share: Decimal
    let usdValue: Decimal
}
