// Sources/Portu/Features/Overview/InspectorPanel.swift
import SwiftUI

struct InspectorPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TopAssetsDonut()
                Divider()
                PriceWatchlist()
            }
            .padding()
        }
    }
}
