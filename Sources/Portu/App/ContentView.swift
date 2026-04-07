import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(store: store)
            } detail: {
                detailView
                    .navigationDestination(for: UUID.self) { assetId in
                        AssetDetailView(assetId: assetId, store: store)
                    }
            }
            StatusBarView(store: store)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.selectedSection {
        case .overview:
            OverviewView(store: store)
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
