import SwiftUI
import SwiftData
import PortuCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    enum Destination: Equatable {
        case overview
        case placeholder(title: String, message: String)
        case accounts
    }

    static func destination(for section: SidebarSection) -> Destination {
        switch section {
        case .overview:
            .overview
        case .exposure:
            .placeholder(
                title: "Exposure",
                message: "Exposure will land in a follow-on plan."
            )
        case .performance:
            .placeholder(
                title: "Performance",
                message: "Performance charts will land in a follow-on plan."
            )
        case .allAssets:
            .placeholder(
                title: "All Assets",
                message: "Asset drill-downs will land in a follow-on plan."
            )
        case .allPositions:
            .placeholder(
                title: "All Positions",
                message: "Position management will land in a follow-on plan."
            )
        case .accounts:
            .accounts
        }
    }

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $appState.selectedSection)
        } detail: {
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
            case .accounts:
                AccountsView()
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
