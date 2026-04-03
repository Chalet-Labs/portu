// Sources/Portu/Features/Overview/OverviewView.swift
import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct OverviewView: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState

    var body: some View {
        HSplitView {
            // Main content (left, flex: 3)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OverviewTopBar {
                        appState.onSyncRequested?()
                    }

                    PortfolioValueChart()

                    OverviewSummaryCards()

                    OverviewPositionTabs()
                }
                .padding()
            }
            .frame(minWidth: 500)
            .layoutPriority(3)

            // Inspector panel (right, flex: 1, collapsible)
            InspectorPanel(store: store)
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
                .layoutPriority(1)
        }
    }
}
