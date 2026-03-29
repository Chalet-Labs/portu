import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
                .navigationDestination(for: UUID.self) { assetId in
                    AssetDetailView(assetId: assetId, store: store)
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .safeAreaInset(edge: .bottom) {
            StatusBarView(store: store)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewView()
        case .exposure:
            ExposureView(store: store)
        case .performance:
            PerformanceView(store: store)
        case .allAssets:
            AllAssetsView(store: store)
        case .allPositions:
            AllPositionsView()
        case .accounts:
            AccountsView(store: store)
        }
    }
}
