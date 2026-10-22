import PortuCore
import SwiftData
import SwiftUI

/// What every valuing view reads besides its own tokens: the override and identity mapping rows,
/// the dashboard settings, the display rate and the USD price books. Each screen adds its methods
/// in an extension in its own folder, and each method fixes which books it reads (the live 24h
/// fractions only where a 24h figure is shown), so a view passes only its own queries.
@MainActor
struct ValuationSources: DynamicProperty {
    @Environment(AppState.self) private var appState
    @Environment(\.historicalMarketPrices) private var historical
    @Query private var overrides: [TokenPricingOverride]
    @Query private var mappings: [TokenIdentityMapping]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    var settings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        overrides.map(TokenPricingOverrideSnapshot.init)
    }

    var mappingSnapshots: [TokenIdentityMappingSnapshot] {
        mappings.map(TokenIdentityMappingSnapshot.init)
    }

    // MARK: - Contexts

    func activeAccounts(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver,
        includingLiveChanges: Bool) -> ValuationContext {
        .activeAccounts(
            tokens,
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            categoryResolver: categoryResolver,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: historical, includingLiveChanges: includingLiveChanges))
    }

    func context(_ inputs: [ValuationInput], includingLiveChanges: Bool) -> ValuationContext {
        ValuationContext(
            inputs: inputs,
            overrides: overrideSnapshots,
            mappings: mappingSnapshots,
            settings: settings,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: historical, includingLiveChanges: includingLiveChanges))
    }
}
