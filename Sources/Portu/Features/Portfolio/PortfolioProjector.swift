import Foundation
import PortuCore
import SwiftData

/// Builds the `PortfolioProjection` from the store, off the main actor (#123). Read-only: it never
/// inserts, changes or saves.
@ModelActor
actor PortfolioProjector {
    /// The entities a build reads. A save touching none of them can't change the projection.
    static let readEntityNames: Set<String> = [
        "Account",
        "Position",
        "PositionToken",
        "Asset",
        "TokenPricingOverride",
        "TokenIdentityMapping",
        "PortfolioCategory",
        "CategorySymbolRule",
        "HistoricalPricePoint"
    ]

    func build(_ request: PortfolioProjectionRequest) throws -> PortfolioProjection {
        let interval = PortfolioTimings.beginProjectionBuild()
        defer { PortfolioTimings.endProjectionBuild(interval) }

        let positions = try modelContext.fetch(FetchDescriptor<Position>())
        try Task.checkCancellation()
        let tokens = try modelContext.fetch(FetchDescriptor<PositionToken>())
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let accounts = try modelContext.fetch(FetchDescriptor<Account>())
        let overrides = try modelContext.fetch(FetchDescriptor<TokenPricingOverride>())
        let mappings = try modelContext.fetch(FetchDescriptor<TokenIdentityMapping>())
        // The same order `OverviewCategorySource` queries them in.
        let categories = try modelContext.fetch(FetchDescriptor<PortfolioCategory>(sortBy: [
            SortDescriptor(\PortfolioCategory.sortOrder),
            SortDescriptor(\PortfolioCategory.name)
        ]))
        let rules = try modelContext.fetch(FetchDescriptor<CategorySymbolRule>(sortBy: [
            SortDescriptor(\CategorySymbolRule.normalizedSymbol)
        ]))
        try Task.checkCancellation()
        // The rows `HistoricalPricesProvider` queries; with backfill off none is read.
        let historicalRows: [HistoricalPricePoint]
        if request.isHistoricalBackfillEnabled {
            let windowStart = MarketPrices.closeWindowStart(now: request.now)
            historicalRows = try modelContext.fetch(FetchDescriptor<HistoricalPricePoint>(
                predicate: #Predicate { $0.day >= windowStart },
                sortBy: [SortDescriptor(\HistoricalPricePoint.day), SortDescriptor(\HistoricalPricePoint.coinGeckoId)]))
        } else {
            historicalRows = []
        }
        try Task.checkCancellation()

        return PortfolioProjection(
            positions: positions,
            tokens: tokens,
            assets: assets,
            accounts: accounts,
            overrides: overrides,
            mappings: mappings,
            categoryResolver: .live(categories: categories, rules: rules),
            historicalRows: historicalRows,
            request: request)
    }

    #if DEBUG
        /// Regression probe for the creation-queue invariant of `PortfolioProjectorClient.live`.
        func isExecutingOnMainThread() -> Bool {
            Thread.isMainThread
        }
    #endif
}
