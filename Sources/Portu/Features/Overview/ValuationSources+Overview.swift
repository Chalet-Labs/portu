import PortuCore

/// The Overview screens, and the Sidebar header that shares the headline.
extension ValuationSources {
    /// The top bar and the Sidebar header: the net total and 24h change of the active portfolio
    /// the provider published.
    func headline(_ portfolio: AllPositionsProjection) -> OverviewHeadline {
        OverviewFeature.headline(context(portfolio.inputs, includingLiveChanges: true))
    }

    func headline(_ positions: [Position]) -> OverviewHeadline {
        headline(AllPositionsProjection(positions))
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

    private func assetCandidates(_ assets: [Asset]) -> [OverviewAssetCandidate] {
        OverviewAssetCandidate.fromAssets(assets, overrides: overrideSnapshots)
    }
}
