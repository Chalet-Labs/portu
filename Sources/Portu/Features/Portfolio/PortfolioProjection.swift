import Foundation
import PortuCore

/// The active portfolio as values, built off the main actor by `PortfolioProjector` once per data
/// change (#123). It holds no model, so it outlives the rows it was built from, and nothing in it
/// depends on a price, the display currency or the dashboard settings.
struct PortfolioProjection: Equatable, Sendable {
    /// The active accounts' inputs, position by position in fetch order, categorized with the
    /// store's rules and prepared (mapped and overridden): the headline input.
    var holdings: [PreparedValuationInput]
    /// The active accounts' inputs in token fetch order, categorized with the default rules and
    /// prepared, each carrying its sync-time value: what polling ranks. Unranked.
    var pollingCandidates: [PreparedValuationInput]
    /// One card per active position, including a position with no token.
    var positionGroups: [AllPositionsCardInfo]
    var assets: [UUID: PortfolioAssetEntry]
    var accounts: [UUID: PortfolioAccountEntry]
    var overrides: [TokenPricingOverrideSnapshot]
    var mappings: [TokenIdentityMappingSnapshot]
    /// The recent-window USD closes and fractions, as `HistoricalMarketPricesFeature.prices` builds them.
    var historical: HistoricalMarketPrices
}

/// An asset as stored: overrides are not applied.
struct PortfolioAssetEntry: Equatable, Sendable {
    let symbol: String
    let name: String
    let category: AssetCategory
    let coinGeckoId: String?
    let logoURL: String?
}

struct PortfolioAccountEntry: Equatable, Sendable {
    let name: String
    let kind: AccountKind
    let isActive: Bool
}

/// What a build depends on besides the store.
struct PortfolioProjectionRequest: Equatable, Sendable {
    var isHistoricalBackfillEnabled: Bool
    var now: Date
}

extension PortfolioProjection {
    /// Projects the store's rows. `positions` and `tokens` keep their fetch order, which decides the
    /// headline's input order and polling's tie-break.
    init(
        positions: [Position],
        tokens: [PositionToken],
        assets: [Asset],
        accounts: [Account],
        overrides: [TokenPricingOverride],
        mappings: [TokenIdentityMapping],
        categoryResolver: PortfolioCategoryResolver,
        historicalRows: [HistoricalPricePoint],
        request: PortfolioProjectionRequest) {
        let overrideSnapshots = overrides.map(TokenPricingOverrideSnapshot.init)
        let mappingSnapshots = mappings.map(TokenIdentityMappingSnapshot.init)
        let headline = ActivePortfolioProjection(positions, categoryResolver: categoryResolver)
        self.init(
            holdings: PortfolioValuation.prepare(headline.inputs, overrides: overrideSnapshots, mappings: mappingSnapshots),
            pollingCandidates: PortfolioValuation.prepare(
                ValuationInput.activeAccounts(tokens, categoryResolver: .defaults),
                overrides: overrideSnapshots,
                mappings: mappingSnapshots),
            positionGroups: headline.cards,
            assets: Dictionary(assets.map { asset in
                (asset.id, PortfolioAssetEntry(
                    symbol: asset.symbol,
                    name: asset.name,
                    category: asset.category,
                    coinGeckoId: asset.coinGeckoId,
                    logoURL: asset.logoURL))
            }, uniquingKeysWith: { first, _ in first }),
            accounts: Dictionary(accounts.map { account in
                (account.id, PortfolioAccountEntry(name: account.name, kind: account.kind, isActive: account.isActive))
            }, uniquingKeysWith: { first, _ in first }),
            overrides: overrideSnapshots,
            mappings: mappingSnapshots,
            historical: HistoricalMarketPricesFeature.prices(
                from: historicalRows,
                isBackfillEnabled: request.isHistoricalBackfillEnabled,
                now: request.now))
    }
}
