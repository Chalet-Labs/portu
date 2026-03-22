import SwiftUI
import SwiftData
import PortuCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $appState.selectedSection)
        } detail: {
            switch appState.selectedSection {
            case .overview:
                PortfolioView()
            case .exposure:
                placeholderView(
                    title: "Exposure",
                    message: "Exposure will land in a follow-on plan."
                )
            case .performance:
                placeholderView(
                    title: "Performance",
                    message: "Performance charts will land in a follow-on plan."
                )
            case .allAssets:
                placeholderView(
                    title: "All Assets",
                    message: "Asset drill-downs will land in a follow-on plan."
                )
            case .allPositions:
                placeholderView(
                    title: "All Positions",
                    message: "Position management will land in a follow-on plan."
                )
            case .accounts:
                placeholderView(
                    title: "Accounts",
                    message: "Account management will land in a follow-on plan."
                )
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
