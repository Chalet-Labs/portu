import ComposableArchitecture
import Foundation
import PortuCore

/// The Overview panels as one revaluation values them (#124): every tab and both donut modes, so a
/// click re-renders from state with no round trip.
struct OverviewValuedOutput: Equatable, Sendable {
    /// The display currency the panels' money is in.
    var currencyCode: String
    var summaryCards: [OverviewSummaryCard]
    var positionTabs: [OverviewPositionTab: OverviewPositionTabData]
    var topAssets: [TopAssetMode: OverviewTopAssets]
    var health: PortfolioHealthData
    var watchlistRows: [OverviewPriceRowData]
}

/// The panels' state, one observed field each, `nil` until the first revaluation. `update` writes
/// each field in place, and the observation macro skips an equal write, so a revaluation that
/// leaves a panel's output equal doesn't re-render it. Never replace the whole value: a new one
/// carries a new identity and notifies every panel.
@ObservableState
struct OverviewPanels: Equatable {
    var currencyCode: String?
    var summaryCards: [OverviewSummaryCard]?
    var positionTabs: [OverviewPositionTab: OverviewPositionTabData]?
    var topAssets: [TopAssetMode: OverviewTopAssets]?
    var health: PortfolioHealthData?
    var watchlistRows: [OverviewPriceRowData]?

    mutating func update(with output: OverviewValuedOutput) {
        currencyCode = output.currencyCode
        summaryCards = output.summaryCards
        positionTabs = output.positionTabs
        topAssets = output.topAssets
        health = output.health
        watchlistRows = output.watchlistRows
    }
}
