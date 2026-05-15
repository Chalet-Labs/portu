// Sources/Portu/Features/Overview/PriceWatchlist.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PriceWatchlist: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historicalPriceChanges24h) private var historicalPriceChanges24h
    @Query private var assets: [Asset]
    @Query private var tokens: [PositionToken]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @AppStorage(OverviewWatchlistStore.key) private var watchlistRaw = "[]"
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true
    @State private var searchText = ""

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(
            tokens,
            categoryResolver: PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules))
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
            prices: appState.prices,
            overrides: overrideSnapshots,
            settings: dashboardSettings)
    }

    private var assetCandidates: [OverviewAssetCandidate] {
        OverviewAssetCandidate.fromAssets(assets, overrides: overrideSnapshots)
    }

    private var assetCandidatesByCoinGeckoId: [String: OverviewAssetCandidate] {
        OverviewFeature.assetCandidatesByCoinGeckoId(from: assetCandidates)
    }

    private var watchlistIDs: [String] {
        OverviewWatchlistStore.decode(watchlistRaw)
    }

    private var rows: [OverviewPriceRowData] {
        OverviewFeature.priceRows(
            tokens: dashboardTokenEntries,
            assetsByCoinGeckoId: assetCandidatesByCoinGeckoId,
            prices: appState.prices,
            changes24h: priceChanges24h,
            watchlistIDs: watchlistIDs)
    }

    private var priceChanges24h: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedChanges24h(
            live: appState.priceChanges24h,
            historical: historicalPriceChanges24h)
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

    private var matchingAssets: [OverviewAssetCandidate] {
        OverviewFeature.watchlistSuggestions(
            assets: assetCandidates,
            watchlistIDs: watchlistIDs,
            query: searchText)
    }

    var body: some View {
        let currentRows = rows
        let currentMatchingAssets = matchingAssets

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Prices")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)

                livePill
                Spacer()
            }

            PriceCountdownText(
                lastPriceUpdate: appState.lastPriceUpdate,
                refreshInterval: PricePollingSettings.refreshIntervalSeconds())

            watchlistSearchField

            if !currentMatchingAssets.isEmpty {
                suggestionList(currentMatchingAssets)
            }

            VStack(spacing: 0) {
                priceHeader

                Rectangle()
                    .fill(PortuTheme.dashboardStroke)
                    .frame(height: 1)

                if currentRows.isEmpty {
                    Text("No priced assets")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                } else {
                    ForEach(currentRows) { row in
                        PriceWatchlistRow(row: row, remove: removeFromWatchlist)

                        Rectangle()
                            .fill(PortuTheme.dashboardStroke.opacity(0.75))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var livePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Live")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(PortuTheme.dashboardSuccess)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(PortuTheme.dashboardSuccess.opacity(0.12)))
        .overlay(
            Capsule(style: .continuous)
                .stroke(PortuTheme.dashboardSuccess.opacity(0.6), lineWidth: 1))
    }

    private var watchlistSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
            TextField("Add to your watchlist...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .onSubmit(addFirstMatch)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PortuTheme.dashboardPanelElevatedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }

    private func suggestionList(_ assets: [OverviewAssetCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(assets) { asset in
                Button {
                    addToWatchlist(asset.coinGeckoId)
                } label: {
                    HStack(spacing: 8) {
                        Text(asset.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PortuTheme.dashboardText)
                            .lineLimit(1)

                        Text(asset.name)
                            .font(.caption)
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(PortuTheme.dashboardGold)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(PortuTheme.dashboardMutedPanelBackground))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var priceHeader: some View {
        HStack(spacing: 6) {
            Text(PriceWatchlistText.priceHeaderTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Price")
                .frame(width: 104, alignment: .trailing)
            Text("24h")
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(PortuTheme.dashboardSecondaryText)
        .lineLimit(1)
        .padding(.bottom, 8)
    }

    private func addFirstMatch() {
        guard let first = matchingAssets.first else { return }
        addToWatchlist(first.coinGeckoId)
    }

    private func addToWatchlist(_ coinGeckoId: String) {
        watchlistRaw = OverviewWatchlistStore.encode(
            OverviewWatchlistStore.add(coinGeckoId, to: watchlistIDs))
        searchText = ""
    }

    private func removeFromWatchlist(_ coinGeckoId: String) {
        watchlistRaw = OverviewWatchlistStore.encode(
            OverviewWatchlistStore.remove(coinGeckoId, from: watchlistIDs))
    }
}

enum PriceWatchlistText {
    static let priceHeaderTitle = "Portfolio + Watchlist"
}

private struct PriceCountdownText: View {
    let lastPriceUpdate: Date?
    let refreshInterval: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("Updating in \(secondsRemaining(at: context.date))s")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
        }
    }

    private func secondsRemaining(at date: Date) -> Int {
        OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: lastPriceUpdate,
            refreshInterval: refreshInterval,
            now: date)
    }
}

private struct PriceWatchlistRow: View {
    let row: OverviewPriceRowData
    let remove: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                assetDot
                Text(OverviewPriceDisplay.assetLabel(row.symbol))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 7)
            .frame(width: 82, height: 25, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PortuTheme.dashboardPanelElevatedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(PortuTheme.dashboardStroke, lineWidth: 1))

            if let price = row.price {
                Text(OverviewPriceDisplay.price(price))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            changeView
                .frame(width: 52, alignment: .trailing)

            if row.isWatchlisted, let coinGeckoId = row.coinGeckoId {
                Button {
                    remove(coinGeckoId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Remove from watchlist")
            }
        }
        .frame(height: 38)
    }

    private var assetDot: some View {
        ZStack {
            Circle()
                .fill(PortuTheme.dashboardGoldMuted)
            Text(String(row.symbol.prefix(1)))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(PortuTheme.dashboardText)
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var changeView: some View {
        if let change = row.change24h {
            HStack(spacing: 3) {
                Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .semibold))
                Text(change, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(change >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
            .lineLimit(1)
        } else {
            Text("-")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardTertiaryText)
                .lineLimit(1)
        }
    }
}
