import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>
    let secretStore: any SecretStore
    @State private var assetNavigationPath = NavigationPath()

    init(
        store: StoreOf<AppFeature>,
        secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        self.store = store
        self.secretStore = secretStore
    }

    var body: some View {
        HistoricalPriceChanges24hProvider {
            mainDashboard
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            store.send(.appLaunched)
            store.send(.startScheduledSync)
        }
        .onDisappear {
            store.send(.stopScheduledSync)
        }
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
                .onChange(of: store.selectedSection) { _, _ in
                    assetNavigationPath = NavigationPath()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            StatusBarView(store: store)
                .environment(\.colorScheme, .dark)
        }
        .background(PortuTheme.dashboardBackground)
    }

    private var detailView: some View {
        sectionView(store.selectedSection)
            .dashboardPage()
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
            AccountsView(store: store, secretStore: secretStore)
        }
    }
}
