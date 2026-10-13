import Foundation
import PortuCore

protocol ExposureRow: Identifiable, Equatable {
    var spotAssets: Decimal { get }
    var liabilities: Decimal { get }
    /// The row's net over the Spot total, a ratio rather than a share (F4); `nil` shows "—".
    var shareOfSpot: Decimal? { get }
}

extension ExposureRow {
    var netExposure: Decimal {
        spotAssets - liabilities
    }
}

nonisolated struct CategoryExposure: ExposureRow {
    let id: String
    let name: String
    let spotAssets: Decimal
    let liabilities: Decimal
    let shareOfSpot: Decimal?
}

nonisolated struct AssetExposure: ExposureRow {
    let id: UUID
    let symbol: String
    let spotAssets: Decimal
    let liabilities: Decimal
    let logoURL: String?
    let shareOfSpot: Decimal?
}

/// The 2×2 summary (S4), in the display currency.
struct ExposureSummary: Equatable {
    /// Gross assets.
    let totalSpot: Decimal
    /// Debt, as a positive amount.
    let totalLiabilities: Decimal
    /// Spot − Liabilities: the Overview net total.
    let netTotal: Decimal
    /// The net of everything outside the stablecoin category.
    let netExposure: Decimal
    /// `netExposure` over the Spot total; `nil` shows "—".
    let netExposureShare: Decimal?
}

struct ExposureDashboardData: Equatable {
    /// The visible rows, in display order.
    let categoryRows: [CategoryExposure]
    let assetRows: [AssetExposure]
    /// Each table's hidden-balances line; `nil` when the table hides nothing.
    let categoryHidden: ExposureHiddenRow?
    let assetHidden: ExposureHiddenRow?
    let summary: ExposureSummary
    let pollingIDs: [String]

    /// The category table as shown: the visible rows, then the hidden line.
    var categoryEntries: [ExposureTableEntry<CategoryExposure>] {
        ExposureTableEntry.entries(categoryRows, hidden: categoryHidden)
    }

    /// The asset table as shown: the visible rows, then the hidden line.
    var assetEntries: [ExposureTableEntry<AssetExposure>] {
        ExposureTableEntry.entries(assetRows, hidden: assetHidden)
    }
}

enum ExposureLabels {
    static let assetCountPillTitle = "Assets"

    /// The hidden line's first cell (F3): "small" when every hidden row is dust.
    static func hiddenRowTitle(rowCount: Int, isAllDust: Bool) -> String {
        "\(rowCount) \(isAllDust ? "small" : "hidden") \(rowCount == 1 ? "balance" : "balances")"
    }
}
