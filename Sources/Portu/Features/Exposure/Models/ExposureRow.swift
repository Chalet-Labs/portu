import Foundation
import PortuCore

struct ExposureRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let assetID: UUID?
    let assetSymbol: String?
    let category: AssetCategory?
    let spotAssets: Decimal
    let liabilities: Decimal
    let derivativesLong: Decimal
    let derivativesShort: Decimal

    var spotNet: Decimal {
        spotAssets - liabilities
    }

    var netExposure: Decimal {
        if category == .stablecoin {
            return .zero
        }

        return spotNet + derivativesLong - derivativesShort
    }
}
