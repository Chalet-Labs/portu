import PortuCore
import SwiftData
import SwiftUI

/// What every Overview view values with besides its own tokens: the override and identity mapping
/// rows, the dashboard settings, the display rate and the USD price books. Each screen has one method
/// here that fixes which books it reads (the live 24h fractions only where a 24h figure is shown), so
/// a view passes only its own queries.
@MainActor
struct OverviewValuationSources: DynamicProperty {
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

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        overrides.map(TokenPricingOverrideSnapshot.init)
    }

    /// The top bar and the Sidebar header: the active portfolio's net total and 24h change.
    func headline(_ positions: [Position]) -> OverviewHeadline {
        OverviewFeature.headline(activePortfolio(positions, categoryResolver: .defaults, includingLiveChanges: true))
    }

    /// The summary cards show no 24h figure, so they do not read the live fractions: a change to
    /// the fractions alone leaves them be. A price tick still re-renders them.
    func summaryCards(_ positions: [Position], categoryResolver: PortfolioCategoryResolver) -> [OverviewSummaryCard] {
        OverviewSummaryCardsFeature.cards(
            activePortfolio(positions, categoryResolver: categoryResolver, includingLiveChanges: false),
            categories: categoryResolver.categories)
    }

    /// One position tab. Only the inputs the tab admits are valued (#103).
    func positionTab(
        _ tab: OverviewPositionTab,
        positions: [Position],
        categoryResolver: PortfolioCategoryResolver) -> OverviewPositionTabData {
        let projected = OverviewPositionProjection.inputs(from: positions, for: tab, categoryResolver: categoryResolver)
        return OverviewPositionProjection.tab(
            tab,
            context: context(projected.inputs, includingLiveChanges: true),
            positions: projected.positions)
    }

    /// A watched coin resolves to the asset a CoinGecko ID override points at, so the candidates
    /// are built here from the store's override rows.
    func watchlistRows(_ tokens: [PositionToken], assets: [Asset], watchlistIDs: [String]) -> [OverviewPriceRowData] {
        OverviewFeature.watchlistRows(
            activeAccounts(tokens, categoryResolver: .defaults, includingLiveChanges: true),
            assets: assetCandidates(assets),
            watchlistIDs: watchlistIDs)
    }

    func watchlistSuggestions(_ assets: [Asset], watchlistIDs: [String], query: String) -> [OverviewAssetCandidate] {
        OverviewFeature.watchlistSuggestions(assets: assetCandidates(assets), watchlistIDs: watchlistIDs, query: query)
    }

    func topAssets(
        _ mode: TopAssetMode,
        tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver) -> OverviewTopAssets {
        OverviewFeature.topAssets(mode, context: activeAccounts(tokens, categoryResolver: categoryResolver, includingLiveChanges: false))
    }

    func health(_ tokens: [PositionToken], categoryResolver: PortfolioCategoryResolver) -> PortfolioHealthData {
        PortfolioHealthFeature.health(activeAccounts(tokens, categoryResolver: categoryResolver, includingLiveChanges: false))
    }

    func pricePollingIDs(_ tokens: [PositionToken], watchlistIDs: [String]) -> [String] {
        OverviewFeature.pricePollingIDs(
            activeAccounts(tokens, categoryResolver: .defaults, includingLiveChanges: false),
            watchlistIDs: watchlistIDs)
    }

    // MARK: - Seam inputs

    private func assetCandidates(_ assets: [Asset]) -> [OverviewAssetCandidate] {
        OverviewAssetCandidate.fromAssets(assets, overrides: overrideSnapshots)
    }

    private func activePortfolio(
        _ positions: [Position],
        categoryResolver: PortfolioCategoryResolver,
        includingLiveChanges: Bool) -> OverviewValuationContext {
        .activePortfolio(
            positions: positions,
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            categoryResolver: categoryResolver,
            appState: appState,
            historical: historical,
            includingLiveChanges: includingLiveChanges)
    }

    private func activeAccounts(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver,
        includingLiveChanges: Bool) -> OverviewValuationContext {
        .activeAccounts(
            tokens,
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            categoryResolver: categoryResolver,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: historical, includingLiveChanges: includingLiveChanges))
    }

    private func context(_ inputs: [ValuationInput], includingLiveChanges: Bool) -> OverviewValuationContext {
        OverviewValuationContext(
            inputs: inputs,
            overrides: overrideSnapshots,
            mappings: mappings.map(TokenIdentityMappingSnapshot.init),
            settings: settings,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: historical, includingLiveChanges: includingLiveChanges))
    }
}

extension OverviewValuationContext {
    /// The dashboard input over the active accounts' tokens, from the store's models.
    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func activeAccounts(
        _ tokens: [PositionToken],
        overrides: [TokenPricingOverride],
        mappings: [TokenIdentityMapping],
        settings: TokenDashboardSettings,
        categoryResolver: PortfolioCategoryResolver = .defaults,
        usdToDisplayRate: Decimal,
        prices: OverviewPriceInputs) -> OverviewValuationContext {
        OverviewValuationContext(
            inputs: ValuationInput.activeAccounts(tokens, categoryResolver: categoryResolver),
            overrides: overrides.map(TokenPricingOverrideSnapshot.init),
            mappings: mappings.map(TokenIdentityMappingSnapshot.init),
            settings: settings,
            usdToDisplayRate: usdToDisplayRate,
            prices: prices)
    }

    /// The input over the active portfolio with the app's USD books. The headline (top bar and
    /// Sidebar header) and the summary cards are built on it, so they can never value a different
    /// portfolio. Inactive accounts' positions are skipped before their tokens are read;
    /// `ValuationInput.activeAccounts` still decides.
    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func activePortfolio(
        positions: [Position],
        overrides: [TokenPricingOverride],
        mappings: [TokenIdentityMapping],
        settings: TokenDashboardSettings,
        categoryResolver: PortfolioCategoryResolver = .defaults,
        appState: AppState,
        historical: HistoricalMarketPrices,
        includingLiveChanges: Bool) -> OverviewValuationContext {
        activeAccounts(
            positions.filter { $0.account?.isActive == true }.flatMap(\.tokens),
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            categoryResolver: categoryResolver,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: historical, includingLiveChanges: includingLiveChanges))
    }
}
