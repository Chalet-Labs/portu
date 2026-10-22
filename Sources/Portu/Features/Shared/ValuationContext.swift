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
    /// The inputs with their overrides and price IDs resolved, when the caller prepared them once
    /// per data change (the read model). They are `inputs` prepared with `overrides` and `mappings`.
    var prepared: [PreparedValuationInput]?

    func valuation(market: MarketPrices? = nil) -> PortfolioValuation {
        if let prepared {
            return PortfolioValuation(prepared: prepared, market: market ?? prices.market)
        }
        return PortfolioValuation(
            inputs: inputs,
            market: market ?? prices.market,
            overrides: overrides,
            mappings: mappings)
    }

    /// The context over prepared inputs, valued without resolving overrides or price IDs again.
    static func prepared( // swiftlint:disable:this function_parameter_count
        _ prepared: [PreparedValuationInput],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot],
        settings: TokenDashboardSettings,
        usdToDisplayRate: Decimal,
        prices: ValuationPriceInputs) -> ValuationContext {
        ValuationContext(
            inputs: prepared.map(\.input),
            overrides: overrides,
            mappings: mappings,
            settings: settings,
            usdToDisplayRate: usdToDisplayRate,
            prices: prices,
            prepared: prepared)
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

@MainActor
extension ValuationContext {
    /// The dashboard input over the active accounts' tokens, from the store's models.
    static func activeAccounts( // swiftlint:disable:this function_parameter_count
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

    /// The input over the active portfolio with the app's USD books, for the summary cards. The
    /// headline (top bar and Sidebar header) values `ActivePortfolioProvider`'s projection instead,
    /// which takes the same active accounts' tokens through the same `ValuationInput.activeAccounts`.
    /// Inactive accounts' positions are skipped before their tokens are read;
    /// `ValuationInput.activeAccounts` still decides.
    static func activePortfolio( // swiftlint:disable:this function_parameter_count
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
