import Foundation
import PortuCore

extension ValuationSources {
    /// All Positions' page over the active accounts. The page shows no 24h figure, so it does not
    /// read the live fractions.
    func allPositions(_ portfolio: ActivePortfolioProjection, filter: AllPositionsFilter) -> AllPositionsPage {
        AllPositionsFeature.page(
            context(portfolio.inputs, includingLiveChanges: false),
            cards: portfolio.cards,
            filter: filter)
    }
}
