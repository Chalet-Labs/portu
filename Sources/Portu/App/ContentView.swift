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
            HStack(spacing: 0) {
                SidebarView(store: store)
                    .frame(width: PortuTheme.dashboardSidebarWidth)
                    .environment(\.colorScheme, .dark)

                Rectangle()
                    .fill(PortuTheme.dashboardStroke)
                    .frame(width: 1)

                NavigationStack(path: $assetNavigationPath) {
                    detailView
                        .navigationDestination(for: UUID.self) { assetId in
                            AssetDetailView(assetId: assetId, store: store)
                                .dashboardPage()
                        }
                }
                .onChange(of: store.detailRoute) { _, _ in
                    assetNavigationPath = NavigationPath()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            StatusBarView(store: store)
                .environment(\.colorScheme, .dark)
        }
        .background(PortuTheme.dashboardBackground)
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.detailRoute {
        case let .section(section):
            sectionView(section)
                .dashboardPage()
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
