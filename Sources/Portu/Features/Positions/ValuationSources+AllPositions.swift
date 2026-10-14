import Foundation
import PortuCore

extension ValuationSources {
    /// All Positions' page over the active accounts. The page shows no 24h figure, so it does not
    /// read the live fractions.
    func allPositions(_ positions: [Position], filter: AllPositionsFilter) -> AllPositionsPage {
        let projection = AllPositionsProjection(positions)
        return AllPositionsFeature.page(
            context(projection.inputs, includingLiveChanges: false),
            cards: projection.cards,
            filter: filter)
    }
}
