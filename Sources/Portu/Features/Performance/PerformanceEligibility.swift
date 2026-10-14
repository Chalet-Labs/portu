import Foundation
import PortuCore

extension PerformanceDataShaping {
    /// Asset IDs that survive dashboard eligibility: the visibility scope shared by the bottom
    /// panel's category changes and price changes (S10).
    ///
    /// Still the per-token legacy rule over the display-currency books, which are passed in until
    /// the module takes over.
    static func visibleAssetIDs(
        _ context: ValuationContext,
        liveDisplayPrices: [String: Decimal] = [:],
        historicalDisplayPrices: [String: Decimal] = [:]) -> Set<UUID> {
        let entries = TokenSettingsFeature.applyIdentityMappings(
            to: context.inputs.map(\.token),
            mappings: context.mappings,
            overrides: context.overrides)
        let prices = OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: liveDisplayPrices,
            historical: historicalDisplayPrices)
        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: entries,
            prices: prices,
            overrides: context.overrides,
            settings: context.settings,
            usdToDisplayRate: context.usdToDisplayRate)
        return Set(eligible.map(\.assetId))
    }
}
