import Foundation
import PortuCore

extension ValuationSources {
    /// The Exposure page over the active accounts. It shows no 24h figure, so it does not read the
    /// live fractions.
    func exposure(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver,
        liveDisplayPrices: [String: Decimal],
        historicalDisplayPrices: [String: Decimal]) -> ExposureDashboardData {
        ExposureFeature.dashboard(
            activeAccounts(tokens, categoryResolver: categoryResolver, includingLiveChanges: false),
            liveDisplayPrices: liveDisplayPrices,
            historicalDisplayPrices: historicalDisplayPrices)
    }
}
