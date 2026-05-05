// Sources/Portu/Features/Overview/InspectorPanel.swift
import ComposableArchitecture
import PortuUI
import SwiftUI

struct InspectorPanel: View {
    let store: StoreOf<AppFeature>
    var showsLeadingDivider = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TopAssetsDonut(store: store)
                inspectorDivider
                PriceWatchlist()
            }
            .padding(18)
        }
        .background(PortuTheme.dashboardPanelBackground)
        .overlay(alignment: .leading) {
            if showsLeadingDivider {
                Rectangle()
                    .fill(PortuTheme.dashboardStroke)
                    .frame(width: 1)
            }
        }
    }

    private var inspectorDivider: some View {
        Rectangle()
            .fill(PortuTheme.dashboardStroke)
            .frame(height: 1)
    }
}
