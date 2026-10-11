import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewView: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    @Environment(\.historicalMarketPrices) private var historicalMarketPrices
    @Query private var allTokens: [PositionToken]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]
    @AppStorage(OverviewWatchlistStore.key) private var watchlistRaw = "[]"
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    private var watchlistIDs: [String] {
        OverviewWatchlistStore.decode(watchlistRaw)
    }

    private var pricePollingIDs: [String] {
        OverviewFeature.pricePollingIDs(
            OverviewValuationContext(
                inputs: ValuationInput.activeAccounts(allTokens),
                overrides: tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init),
                mappings: tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init),
                settings: dashboardSettings,
                usdToDisplayRate: appState.currentUSDToDisplayRate,
                prices: OverviewPriceInputs(
                    livePricesUSD: appState.livePricesUSD,
                    historical: historicalMarketPrices,
                    liveDisplayPrices: appState.prices,
                    historicalDisplayPrices: historicalDisplayPrices)),
            watchlistIDs: watchlistIDs)
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    var body: some View {
        let pollingIDs = pricePollingIDs

        GeometryReader { proxy in
            let isWide = proxy.size.width >= 1080

            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            pageHeader
                                .padding(.horizontal, DashboardStyle.pagePadding)
                                .padding(.top, DashboardStyle.pagePadding)
                                .padding(.bottom, 10)

                            mainScrollColumn
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        InspectorPanel(store: store)
                            .frame(width: PortuTheme.dashboardInspectorWidth + OverviewLayout.inspectorRailWidthAdjustment)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        pageHeader
                            .padding(.horizontal, DashboardStyle.pagePadding)
                            .padding(.top, DashboardStyle.pagePadding)
                            .padding(.bottom, 10)

                        compactScrollColumn
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(PortuTheme.dashboardBackground)
        }
        .dashboardPage()
        // The IDs come ranked by value, so live prices reorder them. Polling is identified
        // by the set, which only changes when a token really enters or leaves.
        .task(id: Set(pollingIDs)) {
            if pollingIDs.isEmpty {
                store.send(.stopPricePolling)
            } else {
                store.send(.startPricePolling(pollingIDs))
            }
        }
        .onDisappear {
            store.send(.stopPricePolling)
        }
    }

    private var pageHeader: some View {
        DashboardPageHeader("Overview") {
            DashboardHeaderSyncActions(
                lastPriceUpdate: store.lastPriceUpdate,
                isSyncing: appState.syncStatus.isSyncing) {
                    appState.onSyncRequested?()
                }
        }
    }

    private var mainScrollColumn: some View {
        ScrollView {
            overviewMainContent
                .padding(.horizontal, DashboardStyle.pagePadding)
                .padding(.bottom, DashboardStyle.pagePadding)
        }
        .background(PortuTheme.dashboardBackground)
    }

    private var compactScrollColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                overviewMainContent
                InspectorPanel(store: store, showsLeadingDivider: false)
                    .dashboardCard(horizontalPadding: 0, verticalPadding: 0)
            }
            .padding(.horizontal, DashboardStyle.pagePadding)
            .padding(.bottom, DashboardStyle.pagePadding)
        }
        .background(PortuTheme.dashboardBackground)
    }

    private var overviewMainContent: some View {
        VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
            DashboardCard {
                HStack(alignment: .top, spacing: 22) {
                    OverviewTopBar()
                        .frame(width: 260, alignment: .leading)

                    PortfolioValueChart()
                        .frame(maxWidth: .infinity)
                }
            }

            OverviewSummaryCards()

            OverviewPositionTabs()
                .dashboardCard(horizontalPadding: 0, verticalPadding: 0)
        }
    }
}

enum OverviewLayout {
    static let inspectorRailWidthAdjustment: CGFloat = 22
}
