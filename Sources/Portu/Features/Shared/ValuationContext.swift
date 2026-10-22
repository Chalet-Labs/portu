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
/// render pass, or once per revaluation for the read model.
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
    /// The valuation with `prices`, computed once by `memoized()`.
    private var memo: PortfolioValuation?

    init(
        inputs: [ValuationInput],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot],
        settings: TokenDashboardSettings,
        usdToDisplayRate: Decimal,
        prices: ValuationPriceInputs,
        prepared: [PreparedValuationInput]? = nil) {
        self.inputs = inputs
        self.overrides = overrides
        self.mappings = mappings
        self.settings = settings
        self.usdToDisplayRate = usdToDisplayRate
        self.prices = prices
        self.prepared = prepared
    }

    func valuation(market: MarketPrices? = nil) -> PortfolioValuation {
        if market == nil, let memo {
            return memo
        }
        if let prepared {
            return PortfolioValuation(prepared: prepared, market: market ?? prices.market)
        }
        return PortfolioValuation(
            inputs: inputs,
            market: market ?? prices.market,
            overrides: overrides,
            mappings: mappings)
    }

    /// The same context, valued once: every seam run over it shares the valuation instead of
    /// valuing the inputs again (#124).
    func memoized() -> ValuationContext {
        var context = self
        context.memo = valuation()
        return context
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
}
