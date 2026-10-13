import Foundation
import PortuCore

/// The USD prices a valuation seam values with (spec I1). The display rate is applied once, after
/// valuation and the display filter.
struct ValuationPriceInputs: Equatable {
    var livePricesUSD: [String: Decimal] = [:]
    /// Live 24h fractions keyed by price ID; merged over the historical ones.
    var liveChanges24h: [String: Decimal] = [:]
    var historical: HistoricalMarketPrices = .empty

    var market: MarketPrices {
        MarketPrices(liveUSD: livePricesUSD, liveChanges24h: liveChanges24h, historical: historical)
    }

    /// The app's USD book. Only views that show a 24h change read the live fractions, so the others
    /// do not re-render on a change to the fractions alone. Every view reads the live prices, and a
    /// poll writes prices and fractions together, so a price tick re-renders them all.
    @MainActor
    static func live(
        _ appState: AppState,
        historical: HistoricalMarketPrices,
        includingLiveChanges: Bool) -> ValuationPriceInputs {
        ValuationPriceInputs(
            livePricesUSD: appState.livePricesUSD,
            liveChanges24h: includingLiveChanges ? appState.priceChanges24h : [:],
            historical: historical)
    }
}

/// Everything a valuation seam values: the inputs and the pricing context, gathered once per
/// render pass.
struct ValuationContext {
    let inputs: [ValuationInput]
    let overrides: [TokenPricingOverrideSnapshot]
    let mappings: [TokenIdentityMappingSnapshot]
    let settings: TokenDashboardSettings
    let usdToDisplayRate: Decimal
    let prices: ValuationPriceInputs

    func valuation(market: MarketPrices? = nil) -> PortfolioValuation {
        PortfolioValuation(
            inputs: inputs,
            market: market ?? prices.market,
            overrides: overrides,
            mappings: mappings)
    }

    /// The same context over a subset of the inputs.
    func restricted(to inputs: [ValuationInput]) -> ValuationContext {
        ValuationContext(
            inputs: inputs,
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            usdToDisplayRate: usdToDisplayRate,
            prices: prices)
    }
}

extension ValuationContext {
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
        prices: ValuationPriceInputs) -> ValuationContext {
        ValuationContext(
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
        includingLiveChanges: Bool) -> ValuationContext {
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
