import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PerformanceBottomPanel: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp) private var snapshots: [AssetSnapshot]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query
    private var historicalPrices: [HistoricalPricePoint]
    @Query private var assets: [Asset]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    init(accountId: UUID?, startDate: Date) {
        self.accountId = accountId
        self.startDate = startDate
        let historicalStartDate = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        _historicalPrices = Query(
            filter: #Predicate<HistoricalPricePoint> { $0.day >= historicalStartDate },
            sort: \.day)
    }

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var categoryChanges: [CategoryChange] {
        let resolver = categoryResolver
        let entries = snapshots
            .filter { s in
                s.timestamp >= startDate && (accountId == nil || s.accountId == accountId)
            }
            .map { CategorySnapshotEntry(snapshot: $0, categoryResolver: resolver) }
        return PerformanceFeature.computeCategoryChanges(entries: entries)
    }

    private var priceChanges: [AssetPricePeriodChange] {
        guard historicalBackfillEnabled else { return [] }
        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        let rows = historicalPrices
            .filter { $0.day >= startDay }
            .map {
                HistoricalPriceEntry(
                    coinGeckoId: $0.coinGeckoId,
                    day: $0.day,
                    usdPrice: $0.usdPrice)
            }

        let heldRows = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: rows,
            holdings: historicalEstimateSnapshotEntries,
            startDate: startDate,
            accountId: accountId,
            isHistoricalBackfillEnabled: historicalBackfillEnabled)

        return PerformanceFeature.computeHistoricalPriceChanges(rows: heldRows)
            .sorted {
                let lhs = absolute($0.percentChange)
                let rhs = absolute($1.percentChange)
                if lhs != rhs { return lhs > rhs }
                return $0.coinGeckoId < $1.coinGeckoId
            }
    }

    private var historicalEstimateSnapshotEntries: [HistoricalEstimateSnapshotEntry] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(
            tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return snapshots.map { snapshot in
            HistoricalEstimateSnapshotEntry(
                accountId: snapshot.accountId,
                assetId: snapshot.assetId,
                timestamp: snapshot.timestamp,
                coinGeckoId: assetsById[snapshot.assetId]?.coinGeckoId,
                coinGeckoIdOverride: overridesByAssetId[snapshot.assetId]?.coinGeckoIdOverride,
                amount: snapshot.amount,
                borrowAmount: snapshot.borrowAmount)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset categories")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                ForEach(categoryChanges) { change in
                    HStack {
                        Text(change.name).frame(width: 100, alignment: .leading)
                        Text(change.startValue, format: .currency(code: "USD")).frame(width: 100)
                        Text("\u{2192}").foregroundStyle(PortuTheme.dashboardSecondaryText)
                        Text(change.endValue, format: .currency(code: "USD")).frame(width: 100)
                        Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(change.percentChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                            .frame(width: 60)
                    }
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Asset prices")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                Text("Top assets with period price change")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                if historicalBackfillEnabled {
                    ForEach(priceChanges.prefix(5)) { change in
                        HStack {
                            Text(change.coinGeckoId)
                                .frame(width: 120, alignment: .leading)
                            Text(change.endPrice, format: .currency(code: "USD"))
                                .frame(width: 90, alignment: .trailing)
                            Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
                                .foregroundStyle(change.percentChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    }
                } else {
                    Text("Historical price backfill disabled")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
        }
        .frame(minHeight: 180, alignment: .topLeading)
    }

    private func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
