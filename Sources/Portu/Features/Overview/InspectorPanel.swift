// Sources/Portu/Features/Overview/InspectorPanel.swift
import ComposableArchitecture
import SwiftUI

struct InspectorPanel: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TopAssetsDonut()
                Divider()
                PortfolioHealthPanel(store: store)
                Divider()
                PriceWatchlist()
            }
            .padding()
        }
    }
}
