import Foundation
import PortuCore

extension ValuationSources {
    /// The All Assets tabs over the active accounts' tokens. No tab shows a 24h figure, so none reads
    /// the live fractions. Protocol names are read here, at the model boundary, for the positions
    /// that contribute an input.
    func allAssets(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver = .defaults) -> AllAssetsInputs {
        let context = activeAccounts(tokens, categoryResolver: categoryResolver, includingLiveChanges: false)
        let positionIDs = Set(context.inputs.map(\.position.positionId))
        var protocolNames: [UUID: String] = [:]
        for token in tokens {
            guard
                let position = token.position,
                positionIDs.contains(position.id),
                protocolNames[position.id] == nil,
                let name = position.protocolName
            else { continue }
            protocolNames[position.id] = name
        }
        return AllAssetsInputs(context: context, protocolNames: protocolNames)
    }
}
