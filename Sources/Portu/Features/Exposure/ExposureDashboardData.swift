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

/// A table's hidden-balances line (F3), shown as its last row: the spot, liabilities and net cells
/// hold the hidden gross, debt and net (decided 2026-10-13).
nonisolated struct ExposureHiddenRow: ExposureRow {
    let rowCount: Int
    /// Every hidden row is dust; otherwise at least one is unpriced.
    let isAllDust: Bool
    let spotAssets: Decimal
    let liabilities: Decimal

    var id: String {
        "hidden"
    }

    /// The line describes a set of rows, so it has no ratio of its own.
    var shareOfSpot: Decimal? {
        nil
    }

    var title: String {
        ExposureLabels.hiddenRowTitle(rowCount: rowCount, isAllDust: isAllDust)
    }

    init(rowCount: Int, isAllDust: Bool, spotAssets: Decimal, liabilities: Decimal) {
        self.rowCount = rowCount
        self.isAllDust = isAllDust
        self.spotAssets = spotAssets
        self.liabilities = liabilities
    }

    /// The display-currency line of a list's hidden rows; `nil` when nothing is hidden.
    init?(_ hidden: HiddenBalances, rate: Decimal) {
        guard !hidden.isEmpty else { return nil }
        let display = hidden.display(rate: rate)
        self.init(rowCount: display.rowCount, isAllDust: display.isAllDust, spotAssets: display.gross, liabilities: display.debt)
    }
}

/// One row of an Exposure table as shown.
enum ExposureTableEntry<Row: ExposureRow>: Identifiable, Equatable {
    case row(Row)
    case hidden(ExposureHiddenRow)

    var id: String {
        switch self {
        case let .row(row): "row-\(row.id)"
        case .hidden: "hidden"
        }
    }

    var hidden: ExposureHiddenRow? {
        if case let .hidden(row) = self {
            return row
        }
        return nil
    }

    /// The visible rows in order, then the hidden line, which is always last.
    static func entries(_ rows: [Row], hidden: ExposureHiddenRow?) -> [Self] {
        rows.map(row) + (hidden.map { [.hidden($0)] } ?? [])
    }
}

enum ExposureLabels {
    static let assetCountPillTitle = "Assets"

    /// The hidden line's first cell (F3): "small" when every hidden row is dust.
    static func hiddenRowTitle(rowCount: Int, isAllDust: Bool) -> String {
        "\(rowCount) \(isAllDust ? "small" : "hidden") \(rowCount == 1 ? "balance" : "balances")"
    }
}
