import Foundation
import PortuCore

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

extension ExposureFeature {
    /// The Exposure page: both tables, the summary and the polled IDs, from one valuation of the
    /// context. `liveDisplayPrices` and `historicalDisplayPrices` are today's display books, which
    /// the page still prices from.
    static func dashboard(
        _ context: ValuationContext,
        liveDisplayPrices: [String: Decimal] = [:],
        historicalDisplayPrices: [String: Decimal] = [:]) -> ExposureDashboardData {
        let tokens = TokenSettingsFeature.applyIdentityMappings(
            to: context.inputs.map(\.token),
            mappings: context.mappings,
            overrides: context.overrides)
        return computeDashboardData(
            tokens: tokens,
            prices: OverviewHistoricalPriceChangeFeature.mergedPrices(
                live: liveDisplayPrices,
                historical: historicalDisplayPrices),
            overrides: context.overrides,
            settings: context.settings,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
    }
}
