import Foundation
import PortuCore

extension PerformanceDataShaping {
    /// Asset IDs that survive dashboard eligibility: the visibility scope shared by the bottom
    /// panel's category changes and price changes (S10).
    ///
    /// One net row per asset, classified by the display filter (A7, F1): dust is judged on the
    /// whole row and everything is USD, so the display rate never enters. Rows are keyed by
    /// `assetId`, which the panel joins on, not by Overview's price-ID + symbol key.
    static func visibleAssetIDs(_ context: ValuationContext) -> Set<UUID> {
        let list = DashboardList(context.valuation().tokens, basis: .net, settings: context.settings) { $0.token.assetId }
        return Set(list.visibleRows.map(\.key))
    }
}
