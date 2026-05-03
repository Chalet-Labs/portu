import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        mainDashboard
            .frame(minWidth: 900, minHeight: 600)
    }

    private var mainDashboard: some View {
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
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.detailRoute {
        case let .section(section):
            sectionView(section)
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: SidebarSection) -> some View {
        switch section {
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
