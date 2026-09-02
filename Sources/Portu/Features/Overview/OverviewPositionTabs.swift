import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewPositionTabs: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historicalPriceChanges24h) private var historicalPriceChanges24h
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    @Query private var allPositions: [Position]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query(sort: [SortDescriptor(\TokenPricingOverride.updatedAt, order: .reverse)])
    private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    @State private var selectedTab: OverviewPositionTab = .keyChanges

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(OverviewPositionTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 12) {
                tabContent
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab.isPlaceholder {
            emptyState(selectedTab.emptyMessage)
        } else {
            let groups = OverviewPositionProjection.groups(
                for: selectedTab,
                positions: positions,
                context: positionContext)

            if groups.isEmpty {
                emptyState(selectedTab.emptyMessage)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups) { group in
                        OverviewPositionGroupCard(
                            group: group,
                            currencyCode: appState.selectedCurrency.displayCode)
                    }
                }
            }
        }
    }

    private func tabButton(_ tab: OverviewPositionTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedTab == tab ? PortuTheme.dashboardGold : .clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardTertiaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    // MARK: - Context

    /// Built fresh on every body evaluation, including tab clicks.
    ///
    /// Deliberately not memoized (issue #98 residual, audited 2026-09-02):
    /// the rebuild — two price-dictionary merges plus small-table maps and
    /// resolver construction — is dominated by the per-tab `groups()`
    /// projection that a tab click runs anyway. A staleness-free `@State`
    /// cache key is buildable today (`PortfolioCategoryResolver` is
    /// `Equatable`, with snapshot-based stored properties), but building and
    /// comparing the key on every body would re-pay most of the rebuild it
    /// avoids. If this ever shows up in Instruments, memoize keyed on those
    /// resolver snapshots.
    private var positionContext: OverviewPositionContext {
        OverviewPositionContext(
            prices: displayPrices,
            changes24h: priceChanges24h,
            overrideMap: overrideMap,
            mappingMap: mappingMap,
            categoryResolver: categoryResolver,
            dashboardSettings: dashboardSettings,
            fallbackUSDToDisplayRate: appState.currentUSDToDisplayRate)
    }

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var overrideMap: [UUID: TokenPricingOverrideSnapshot] {
        TokenSettingsFeature.overridesByAssetId(tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
    }

    private var mappingMap: [OnchainTokenIdentity: TokenIdentityMappingSnapshot] {
        TokenIdentityMappingFeature.mappingsByIdentity(tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init))
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var displayPrices: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: appState.prices,
            historical: historicalDisplayPrices)
    }

    private var priceChanges24h: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedChanges24h(
            live: appState.priceChanges24h,
            historical: historicalPriceChanges24h)
    }
}
