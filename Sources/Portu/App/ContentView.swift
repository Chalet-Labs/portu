import SwiftUI
import SwiftData
import PortuCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
                .navigationDestination(for: UUID.self) { assetId in
                    Text("Asset Detail: \(assetId)")
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewView()
        case .exposure:
            placeholderView("Exposure", icon: "chart.bar.xaxis")
        case .performance:
            placeholderView("Performance", icon: "chart.line.uptrend.xyaxis")
        case .allAssets:
            AllAssetsView()
        case .allPositions:
            placeholderView("All Positions", icon: "list.bullet.rectangle")
        case .accounts:
            placeholderView("Accounts", icon: "person.2")
        }
    }

    private func placeholderView(_ title: String, icon: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text("Coming in a future plan"))
    }
}
