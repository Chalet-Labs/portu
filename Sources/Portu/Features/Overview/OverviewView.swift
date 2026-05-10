// Sources/Portu/Features/Overview/OverviewView.swift
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewView: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState
    @Query private var allTokens: [PositionToken]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @AppStorage(OverviewWatchlistStore.key) private var watchlistRaw = "[]"

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(allTokens)
    }

    private var watchlistIDs: [String] {
        OverviewWatchlistStore.decode(watchlistRaw)
    }

    private var pricePollingIDs: [String] {
        OverviewFeature.pricePollingIDs(
            tokens: tokenEntries,
            watchlistIDs: watchlistIDs,
            overrides: overrideSnapshots)
    }

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init)
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 1080

            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                    .padding(.horizontal, DashboardStyle.pagePadding)
                    .padding(.top, DashboardStyle.pagePadding)
                    .padding(.bottom, 10)

                if isWide {
                    HStack(alignment: .top, spacing: 0) {
                        mainScrollColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        InspectorPanel(store: store)
                            .frame(width: PortuTheme.dashboardInspectorWidth + OverviewLayout.inspectorRailWidthAdjustment)
                    }
                } else {
                    compactScrollColumn
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PortuTheme.dashboardBackground)
        }
        .dashboardPage()
        .task(id: pricePollingIDs) {
            if pricePollingIDs.isEmpty {
                store.send(.stopPricePolling)
            } else {
                store.send(.startPricePolling(pricePollingIDs))
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
