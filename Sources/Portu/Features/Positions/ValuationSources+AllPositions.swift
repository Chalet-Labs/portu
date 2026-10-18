import Foundation
import PortuCore

extension ValuationSources {
    /// All Positions' page over the active accounts. The page shows no 24h figure, so it does not
    /// read the live fractions.
    func allPositions(_ portfolio: AllPositionsProjection, filter: AllPositionsFilter) -> AllPositionsPage {
        AllPositionsFeature.page(
            context(portfolio.inputs, includingLiveChanges: false),
            cards: portfolio.cards,
            filter: filter)
    }

    func allPositions(_ positions: [Position], filter: AllPositionsFilter) -> AllPositionsPage {
        allPositions(AllPositionsProjection(positions), filter: filter)
    }
}
