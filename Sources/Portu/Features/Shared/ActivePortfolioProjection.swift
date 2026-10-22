import Foundation
import PortuCore

/// The boundary between SwiftData and the dashboard's active portfolio.
///
/// `SyncEngine` deletes and reinserts `Position` rows while SwiftUI may still be evaluating a body,
/// and reading a deleted model's property terminates the process (#103). `ActivePortfolioProvider`
/// builds this once per store change for All Positions, and `PortfolioProjector` builds it off the
/// main actor for the portfolio read model (#123); readers hold only its values.
struct ActivePortfolioProjection: Equatable, Sendable {
    /// The active accounts' valuation inputs.
    let inputs: [ValuationInput]
    /// Every active position, in query order, including one with no token.
    let cards: [AllPositionsCardInfo]

    init(inputs: [ValuationInput], cards: [AllPositionsCardInfo]) {
        self.inputs = inputs
        self.cards = cards
    }

    /// Reads the models on the caller's actor: the main actor for `ActivePortfolioProvider`, the
    /// `PortfolioProjector` for the read model.
    init(_ positions: [Position], categoryResolver: PortfolioCategoryResolver = .defaults) {
        let active = positions.filter { $0.account?.isActive == true }
        self.inputs = ValuationInput.activeAccounts(active.flatMap(\.tokens), categoryResolver: categoryResolver)
        self.cards = active.map { position in
            AllPositionsCardInfo(
                id: position.id,
                positionType: position.positionType,
                protocolId: position.protocolId,
                protocolName: position.protocolName,
                chain: position.chain,
                healthFactor: position.healthFactor)
        }
    }
}
