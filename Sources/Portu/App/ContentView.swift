import SwiftUI
import SwiftData
import PortuCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    static let assetDestinationTypeName = "Asset.ID"

    enum Destination: Equatable {
        case overview
        case placeholder(title: String, message: String)
        case exposure
        case performance
        case accounts
        case allAssets
        case allPositions
    }

    static func destination(for section: SidebarSection) -> Destination {
        switch section {
        case .overview:
            .overview
        case .exposure:
            .exposure
        case .performance:
            .performance
        case .allAssets:
            .allAssets
        case .allPositions:
            .allPositions
        case .accounts:
            .accounts
        }
    }

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $appState.selectedSection)
        } detail: {
            Group {
                switch Self.destination(for: appState.selectedSection) {
                case .overview:
                    HSplitView {
                        PortfolioView()
                            .frame(minWidth: 700, maxWidth: .infinity)
                            .layoutPriority(1)

                        OverviewInspector()
                    }
                case let .placeholder(title, message):
                    placeholderView(title: title, message: message)
                case .exposure:
                    ExposureView()
                case .performance:
                    PerformanceView()
                case .accounts:
                    AccountsView()
                case .allAssets:
                    AllAssetsView()
                case .allPositions:
                    AllPositionsView()
                }
            }
            .navigationDestination(for: Asset.ID.self) { assetID in
                AssetDetailView(assetID: assetID)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Sync", systemImage: "arrow.clockwise") {
                    // TODO: Trigger SyncEngine when overview navigation is in place.
                }
            }
        }
    }

    @ViewBuilder
    private func placeholderView(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "hammer")
        } description: {
            Text(message)
        }
        .navigationTitle(title)
    }
}
