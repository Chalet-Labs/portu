import ComposableArchitecture
import Foundation
import PortuCore

// swiftformat:disable redundantSendable

/// The prices a revaluation reads, all owned by `AppFeature.State`.
struct PortfolioPriceInputs: Equatable, Sendable {
    var livePricesUSD: [String: Decimal]
    var liveChanges24h: [String: Decimal]
    var usdToDisplayRate: Decimal
    var currency: FiatCurrency
}

struct PortfolioValuationRequest: Sendable {
    var projection: PortfolioProjection
    var prices: PortfolioPriceInputs
    var settings: DashboardSettings
}

/// What the slice renders and what Overview polls: one revaluation's result.
struct PortfolioValuedOutput: Equatable, Sendable {
    /// In the display currency of `currencyCode`.
    var headline: OverviewHeadline
    var currencyCode: String
    /// The holdings ranked by live value, capped, then the watchlist: today's Overview rules.
    var pricePollingIDs: [String]
}

/// One revaluation: the headline and polling IDs, and the Overview panels (#124).
struct PortfolioRevaluation: Equatable, Sendable {
    var valued: PortfolioValuedOutput
    var overview: OverviewValuedOutput
}

/// Values the projection with the current prices (#123). A dependency so tests count revaluations
/// and hold one open to prove a newer one wins; the per-tick valuation itself is synchronous.
struct PortfolioValuator {
    var value: @Sendable (PortfolioValuationRequest) async -> PortfolioRevaluation
}

extension PortfolioValuator: DependencyKey {
    static let liveValue = Self { request in
        PortfolioTimings.measureValuation { compute(request) }
    }

    static let testValue = Self { compute($0) }
}

extension DependencyValues {
    var portfolioValuator: PortfolioValuator {
        get { self[PortfolioValuator.self] }
        set { self[PortfolioValuator.self] = newValue }
    }
}

extension PortfolioValuator {
    /// Values on the concurrent executor whatever the caller's isolation: the per-tick valuation
    /// misses its main-thread budget on the real store (#123 spec V3).
    @concurrent
    func valueOffMain(_ request: PortfolioValuationRequest) async -> PortfolioRevaluation {
        await value(request)
    }
}

extension PortfolioValuator {
    /// Today's Overview seams over the prepared projection. Each list is valued once, with the live
    /// 24h fractions, and every seam over it shares that valuation: the panels that show no 24h
    /// figure (cards, donut, health, polling) read neither fraction nor change, so the fractions
    /// leave them as they were without.
    static func compute(_ request: PortfolioValuationRequest) -> PortfolioRevaluation {
        let projection = request.projection
        let prices = request.prices
        let settings = request.settings
        let context = { (inputs: [PreparedValuationInput]) in
            ValuationContext.prepared(
                inputs,
                overrides: projection.overrides,
                mappings: projection.mappings,
                settings: settings.dashboard,
                usdToDisplayRate: prices.usdToDisplayRate,
                prices: ValuationPriceInputs(
                    livePricesUSD: prices.livePricesUSD,
                    liveChanges24h: prices.liveChanges24h,
                    historical: projection.historical))
                .memoized()
        }
        let holdings = context(projection.holdings)
        let tokens = context(projection.activeTokens)
        let currencyCode = prices.currency.displayCode
        return PortfolioRevaluation(
            valued: PortfolioValuedOutput(
                headline: OverviewFeature.headline(holdings),
                currencyCode: currencyCode,
                pricePollingIDs: OverviewFeature.pricePollingIDs(tokens, watchlistIDs: settings.watchlistIDs)),
            overview: OverviewValuedOutput(
                currencyCode: currencyCode,
                summaryCards: OverviewSummaryCardsFeature.cards(holdings, categories: projection.categories),
                positionTabs: Dictionary(uniqueKeysWithValues: OverviewPositionTab.allCases.map { tab in
                    (tab, OverviewPositionProjection.tab(tab, context: holdings, positions: projection.positionMeta))
                }),
                topAssets: Dictionary(uniqueKeysWithValues: TopAssetMode.allCases.map { mode in
                    (mode, OverviewFeature.topAssets(mode, context: tokens))
                }),
                health: PortfolioHealthFeature.health(tokens),
                watchlistRows: OverviewFeature.watchlistRows(
                    tokens,
                    assets: projection.watchlistCandidates,
                    watchlistIDs: settings.watchlistIDs)))
    }
}
