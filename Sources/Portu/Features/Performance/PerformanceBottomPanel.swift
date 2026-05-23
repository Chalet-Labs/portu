import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PerformanceBottomPanel: View {
    let accountId: UUID?
    let startDate: Date

    @Environment(AppState.self) private var appState
    @Environment(\.historicalPricesUSD) private var historicalPricesUSD

    @Query(sort: \AssetSnapshot.timestamp) private var snapshots: [AssetSnapshot]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query
    private var historicalPrices: [HistoricalPricePoint]
    @Query private var assets: [Asset]
    @Query private var tokens: [PositionToken]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]

    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

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

    private var selectedTokens: [PositionToken] {
        guard let accountId else { return tokens }
        return tokens.filter { $0.position?.account?.id == accountId }
    }

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(
            selectedTokens,
            categoryResolver: categoryResolver)
    }

    private var mappedTokenEntries: [TokenEntry] {
        TokenSettingsFeature.applyIdentityMappings(
            to: tokenEntries,
            mappings: mappingSnapshots,
            overrides: overrideSnapshots)
    }

    private var dashboardTokenEntries: [TokenEntry] {
        TokenSettingsFeature.dashboardEligibleTokens(
            tokens: mappedTokenEntries,
            prices: displayPrices,
            overrides: overrideSnapshots,
            settings: dashboardSettings)
    }

    private var dashboardVisibleAssetIDs: Set<UUID> {
        Set(dashboardTokenEntries.map(\.assetId))
    }

    private var categoryChanges: [CategoryChange] {
        let resolver = categoryResolver
        let visibleAssetIDs = dashboardVisibleAssetIDs
        guard !visibleAssetIDs.isEmpty else { return [] }
        let entries = snapshots
            .filter { s in
                s.timestamp >= startDate
                    && (accountId == nil || s.accountId == accountId)
                    && visibleAssetIDs.contains(s.assetId)
            }
            .map { CategorySnapshotEntry(snapshot: $0, categoryResolver: resolver) }
        return PerformanceFeature.computeCategoryChanges(
            entries: entries,
            visibleAssetIDs: visibleAssetIDs)
    }

    private var priceChanges: [AssetPricePeriodChange] {
        guard historicalBackfillEnabled else { return [] }
        let visibleHoldings = visibleHistoricalEstimateSnapshotEntries
        guard !visibleHoldings.isEmpty else { return [] }
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
            holdings: visibleHoldings,
            startDate: startDate,
            accountId: accountId,
            isHistoricalBackfillEnabled: historicalBackfillEnabled)

        return PerformanceFeature.applyAssetDisplayNames(
            changes: PerformanceFeature.computeHistoricalPriceChanges(rows: heldRows),
            namesByHistoricalPriceID: assetNamesByHistoricalPriceID)
            .sorted {
                let lhs = absolute($0.percentChange)
                let rhs = absolute($1.percentChange)
                if lhs != rhs { return lhs > rhs }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var visibleHistoricalEstimateSnapshotEntries: [HistoricalEstimateSnapshotEntry] {
        let visibleAssetIDs = dashboardVisibleAssetIDs
        guard !visibleAssetIDs.isEmpty else { return [] }
        return historicalEstimateSnapshotEntries.filter { visibleAssetIDs.contains($0.assetId) }
    }

    private var historicalEstimateSnapshotEntries: [HistoricalEstimateSnapshotEntry] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(overrideSnapshots)
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return snapshots.map { snapshot in
            let asset = assetsById[snapshot.assetId]
            return HistoricalEstimateSnapshotEntry(
                accountId: snapshot.accountId,
                assetId: snapshot.assetId,
                timestamp: snapshot.timestamp,
                coinGeckoId: asset?.coinGeckoId,
                coinGeckoIdOverride: overridesByAssetId[snapshot.assetId]?.coinGeckoIdOverride,
                onchainIdentity: OnchainTokenIdentity(chain: asset?.upsertChain, contractAddress: asset?.upsertContract),
                amount: snapshot.amount,
                borrowAmount: snapshot.borrowAmount,
                netUSDValue: snapshot.usdValue - snapshot.borrowUsdValue)
        }
    }

    private var displayPrices: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: appState.prices,
            historical: historicalPricesUSD)
    }

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init)
    }

    private var mappingSnapshots: [TokenIdentityMappingSnapshot] {
        tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init)
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var assetNamesByHistoricalPriceID: [String: String] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(overrideSnapshots)
        let mappingsByIdentity = TokenIdentityMappingFeature.mappingsByIdentity(mappingSnapshots)
        var names: [String: String] = [:]

        for asset in assets.sorted(by: sortAssetNames) {
            let name = displayName(for: asset)
            let identity = OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract)

            recordName(name, for: overridesByAssetId[asset.id]?.coinGeckoIdOverride, in: &names)
            recordName(name, for: asset.coinGeckoId, in: &names)
            recordName(name, for: TokenIdentityMappingFeature.nativeCoinGeckoID(for: identity), in: &names)
            recordName(name, for: TokenIdentityMappingFeature.knownContractCoinGeckoID(for: identity), in: &names)
            recordName(name, for: identity?.historicalPriceID, in: &names)

            if let identity, let mapping = mappingsByIdentity[identity] {
                recordName(name, for: mapping.coinGeckoId, in: &names)
                recordName(name, for: mapping.zapperId, in: &names)
            }
        }

        return names
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
                            Text(change.name)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(2)
                                .truncationMode(.tail)
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

    private func recordName(_ name: String, for id: String?, in names: inout [String: String]) {
        guard let normalizedID = TokenIdentityMappingFeature.normalizedHistoricalPriceID(id) else { return }
        names[normalizedID] = names[normalizedID] ?? name
    }

    private func displayName(for asset: Asset) -> String {
        let trimmedName = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }

        let trimmedSymbol = asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSymbol.isEmpty ? "Unknown asset" : trimmedSymbol
    }

    private func sortAssetNames(_ lhs: Asset, _ rhs: Asset) -> Bool {
        let lhsName = displayName(for: lhs)
        let rhsName = displayName(for: rhs)
        let nameOrder = lhsName.localizedStandardCompare(rhsName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
