import Foundation
import PortuCore

/// The active portfolio as values, built off the main actor by `PortfolioProjector` once per data
/// change (#123). It holds no model, so it outlives the rows it was built from, and nothing in it
/// depends on a price, the display currency or the dashboard settings.
struct PortfolioProjection: Equatable, Sendable {
    /// The active accounts' inputs, position by position in fetch order, categorized with the
    /// store's rules and prepared (mapped and overridden): the headline, the summary cards and the
    /// position tabs.
    var holdings: [PreparedValuationInput]
    /// The same tokens in token fetch order, each carrying its sync-time value: what polling ranks,
    /// and the watchlist, the donut and health. Unranked. Polling and the watchlist read no
    /// category, so the store's rules leave them as the default rules did.
    var activeTokens: [PreparedValuationInput]
    /// One card per active position, including a position with no token.
    var positionGroups: [AllPositionsCardInfo]
    /// Every active position's title, type and chain, for the position tabs.
    var positionMeta: [UUID: OverviewPositionMeta]
    var assets: [UUID: PortfolioAssetEntry]
    var accounts: [UUID: PortfolioAccountEntry]
    var overrides: [TokenPricingOverrideSnapshot]
    var mappings: [TokenIdentityMappingSnapshot]
    /// The store's categories, or the defaults when it has none: the summary cards' majors label.
    var categories: [PortfolioCategorySnapshot]
    /// Every asset with a CoinGecko ID (the override's first), in fetch order: what the watchlist
    /// can add and how a watched coin finds its asset.
    var watchlistCandidates: [OverviewAssetCandidate]
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
    /// Projects the store's rows. `positions`, `tokens` and `assets` keep their fetch order, which
    /// decides the headline's input order, polling's tie-break and the order labels are taken in.
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
            activeTokens: PortfolioValuation.prepare(
                ValuationInput.activeAccounts(tokens, categoryResolver: categoryResolver),
                overrides: overrideSnapshots,
                mappings: mappingSnapshots),
            positionGroups: headline.cards,
            positionMeta: Dictionary(
                positions.lazy.filter { $0.account?.isActive == true }.map { ($0.id, OverviewPositionMeta($0)) },
                uniquingKeysWith: { first, _ in first }),
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
            categories: categoryResolver.categories,
            watchlistCandidates: OverviewAssetCandidate.fromAssets(assets, overrides: overrideSnapshots),
            historical: HistoricalMarketPricesFeature.prices(
                from: historicalRows,
                isBackfillEnabled: request.isHistoricalBackfillEnabled,
                now: request.now))
    }
}
