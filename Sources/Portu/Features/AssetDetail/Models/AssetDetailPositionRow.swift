import Foundation

struct AssetDetailPositionRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let accountName: String
    let platformName: String
    let contextLabel: String
    let networkName: String
    let amount: Decimal
    let usdBalance: Decimal
}
