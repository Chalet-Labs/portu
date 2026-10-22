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

/// Values the projection with the current prices (#123). A dependency so tests count revaluations,
/// and so the per-tick budget's fallback (an off-main effect) has a seam.
struct PortfolioValuator {
    var value: @Sendable (PortfolioValuationRequest) -> PortfolioValuedOutput
}

extension PortfolioValuator: DependencyKey {
    static let liveValue = Self { request in
        PortfolioTimings.measureValuation { compute(request) }
    }

    static let testValue = Self(value: compute)
}

extension DependencyValues {
    var portfolioValuator: PortfolioValuator {
        get { self[PortfolioValuator.self] }
        set { self[PortfolioValuator.self] = newValue }
    }
}

extension PortfolioValuator {
    /// Today's Overview seams over the prepared projection: the headline values the holdings with
    /// the live 24h fractions; polling values the candidates without them, as the Overview view
    /// did when it ranked its own query.
    static func compute(_ request: PortfolioValuationRequest) -> PortfolioValuedOutput {
        let projection = request.projection
        let prices = request.prices
        let context = { (inputs: [PreparedValuationInput], includingLiveChanges: Bool) in
            ValuationContext.prepared(
                inputs,
                overrides: projection.overrides,
                mappings: projection.mappings,
                settings: request.settings.dashboard,
                usdToDisplayRate: prices.usdToDisplayRate,
                prices: ValuationPriceInputs(
                    livePricesUSD: prices.livePricesUSD,
                    liveChanges24h: includingLiveChanges ? prices.liveChanges24h : [:],
                    historical: projection.historical))
        }
        return PortfolioValuedOutput(
            headline: OverviewFeature.headline(context(projection.holdings, true)),
            currencyCode: prices.currency.displayCode,
            pricePollingIDs: OverviewFeature.pricePollingIDs(
                context(projection.pollingCandidates, false),
                watchlistIDs: request.settings.watchlistIDs))
    }
}
