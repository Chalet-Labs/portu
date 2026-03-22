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
            case .account(let id):
                AccountDetailView(accountID: id)
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
}
