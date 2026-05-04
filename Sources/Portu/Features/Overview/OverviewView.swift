// Sources/Portu/Features/Overview/OverviewView.swift
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewView: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                    DashboardPageHeader("Overview") {
                        HStack(spacing: 10) {
                            if let lastPriceUpdate = store.lastPriceUpdate {
                                Text("Updated \(lastPriceUpdate, format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            } else {
                                Text("Not updated yet")
                                    .font(.caption)
                                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            }

                            if case .syncing = appState.syncStatus {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(PortuTheme.dashboardGold)
                            } else {
                                Button {
                                    appState.onSyncRequested?()
                                } label: {
                                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .dashboardControl()
                            }
                        }
                    }

                    DashboardCard {
                        HStack(alignment: .top, spacing: 20) {
                            OverviewTopBar()
                                .frame(width: 250, alignment: .leading)

                            PortfolioValueChart()
                                .frame(maxWidth: .infinity)
                        }
                    }

                    OverviewSummaryCards()

                    OverviewPositionTabs()
                        .dashboardCard()
                }
                .padding(DashboardStyle.pagePadding)
            }
            .frame(minWidth: 500)
            .layoutPriority(3)
            .background(PortuTheme.dashboardBackground)

            InspectorPanel(store: store)
                .frame(
                    minWidth: PortuTheme.dashboardInspectorWidth,
                    idealWidth: PortuTheme.dashboardInspectorWidth,
                    maxWidth: 360)
                .layoutPriority(1)
        }
        .dashboardPage()
    }
}
