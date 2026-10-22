import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

struct OverviewView: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState

    var body: some View {
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
        .background {
            OverviewPricePollingDriver(store: store)
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
                    OverviewTopBar(store: store.scope(state: \.portfolio, action: \.portfolio))
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

/// Starts and stops polling with the portfolio read model's IDs (#123). Polling stays owned by the
/// view until #101. It sits in its own view so only it re-renders when the IDs' ranking moves with
/// a tick, and it polls nothing before the first projection build, so launch never starts a
/// watchlist-only poll first.
private struct OverviewPricePollingDriver: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        let pollingIDs = store.portfolio.valued?.pricePollingIDs

        Color.clear
            // The IDs come ranked by value, so live prices reorder them. Polling is identified
            // by the set, which only changes when a token really enters or leaves.
            .task(id: pollingIDs.map(Set.init)) {
                guard let pollingIDs else { return }
                if pollingIDs.isEmpty {
                    store.send(.stopPricePolling)
                } else {
                    store.send(.startPricePolling(pollingIDs))
                }
            }
    }
}

enum OverviewLayout {
    static let inspectorRailWidthAdjustment: CGFloat = 22
}
