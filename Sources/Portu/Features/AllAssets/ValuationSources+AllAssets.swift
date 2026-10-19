import Foundation
import PortuCore

extension ValuationSources {
    /// The All Assets tabs' context over the active accounts' tokens. No tab shows a 24h figure, so
    /// none reads the live fractions.
    func allAssets(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver = .defaults) -> ValuationContext {
        activeAccounts(tokens, categoryResolver: categoryResolver, includingLiveChanges: false)
    }

    /// The Platforms tab. Only it names its rows by protocol, so only it reads the protocol names,
    /// here at the model boundary, for the positions that contribute an input.
    func platforms(_ tokens: [PositionToken]) -> PlatformsTabData {
        let context = allAssets(tokens)
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
        return AllAssetsFeature.platforms(context, protocolNames: protocolNames)
    }
}
