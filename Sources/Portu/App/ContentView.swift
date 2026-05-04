import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>
    @State private var assetNavigationPath = NavigationPath()

    var body: some View {
        mainDashboard
            .frame(minWidth: 900, minHeight: 600)
    }

    private var mainDashboard: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(
                        min: PortuTheme.dashboardSidebarWidth,
                        ideal: PortuTheme.dashboardSidebarWidth,
                        max: PortuTheme.dashboardSidebarWidth)
            } detail: {
                NavigationStack(path: $assetNavigationPath) {
                    detailView
                        .dashboardPage()
                        .navigationDestination(for: UUID.self) { assetId in
                            AssetDetailView(assetId: assetId, store: store)
                        }
                }
                .onChange(of: store.detailRoute) { _, _ in
                    assetNavigationPath = NavigationPath()
                }
            }
            StatusBarView(store: store)
        }
        .background(PortuTheme.dashboardBackground)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.detailRoute {
        case let .section(section):
            sectionView(section)
        case .settings:
            SettingsView()
                .environment(\.colorScheme, .light)
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
