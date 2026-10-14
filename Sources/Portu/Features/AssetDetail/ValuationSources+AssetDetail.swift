import Foundation
import PortuCore

extension ValuationSources {
    /// Asset Detail over the active accounts' tokens of one asset. The header shows a 24h figure, so
    /// it reads the live fractions.
    func assetDetail(_ projection: AssetDetailProjection, legacyDisplayPrices: [String: Decimal] = [:]) -> AssetDetailPage {
        AssetDetailFeature.page(
            context(projection.inputs, includingLiveChanges: true),
            asset: projection.asset,
            labels: projection.labels,
            legacyDisplayPrices: legacyDisplayPrices)
    }
}
