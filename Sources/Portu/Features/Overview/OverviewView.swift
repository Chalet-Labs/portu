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
    @AppStorage(OverviewWatchlistStore.key) private var watchlistRaw = "[]"

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(allTokens)
    }

    private var watchlistIDs: [String] {
        OverviewWatchlistStore.decode(watchlistRaw)
    }

    private var pricePollingIDs: [String] {
        OverviewFeature.pricePollingIDs(tokens: tokenEntries, watchlistIDs: watchlistIDs)
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
            HStack(spacing: 12) {
                if let lastPriceUpdate = store.lastPriceUpdate {
                    Text("Updated \(lastPriceUpdate, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                } else {
                    Text("Not updated yet")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                }

                if case .syncing = appState.syncStatus {
                    Button {} label: {
                        OverviewSyncButtonLabel(isSyncing: true)
                    }
                    .buttonStyle(OverviewSyncButtonStyle())
                    .disabled(true)
                } else {
                    Button {
                        appState.onSyncRequested?()
                    } label: {
                        OverviewSyncButtonLabel(isSyncing: false)
                    }
                    .buttonStyle(OverviewSyncButtonStyle())
                }
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

enum OverviewSyncButtonStyleMetrics {
    static let iconName = "arrow.triangle.2.circlepath"
    static let height: CGFloat = 30
    static let cornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 11
    static let labelSpacing: CGFloat = 7
}

private struct OverviewSyncButtonLabel: View {
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: OverviewSyncButtonStyleMetrics.labelSpacing) {
            Text("Sync")
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.62)
                    .frame(width: 12, height: 12)
                    .tint(PortuTheme.dashboardGold)
            } else {
                Image(systemName: OverviewSyncButtonStyleMetrics.iconName)
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .lineLimit(1)
    }
}

private struct OverviewSyncButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? PortuTheme.dashboardText : PortuTheme.dashboardTertiaryText)
            .padding(.horizontal, OverviewSyncButtonStyleMetrics.horizontalPadding)
            .frame(height: OverviewSyncButtonStyleMetrics.height)
            .background(
                RoundedRectangle(cornerRadius: OverviewSyncButtonStyleMetrics.cornerRadius, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed)))
            .overlay(
                RoundedRectangle(cornerRadius: OverviewSyncButtonStyleMetrics.cornerRadius, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1))
            .contentShape(
                RoundedRectangle(cornerRadius: OverviewSyncButtonStyleMetrics.cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.72)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return PortuTheme.dashboardGoldMuted.opacity(0.52)
        }
        return PortuTheme.dashboardGoldMuted.opacity(0.34)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed {
            return PortuTheme.dashboardGold.opacity(0.58)
        }
        return PortuTheme.dashboardGold.opacity(0.34)
    }
}
