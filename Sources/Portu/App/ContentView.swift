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
            case .accounts:
                AccountDetailView(accountID: nil)
            default:
                ContentUnavailableView(
                    appState.selectedSection.displayName,
                    systemImage: "hammer",
                    description: Text("Coming in a future plan")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    // TODO: Trigger sync
                }
            }
        }
    }
}

extension SidebarSection {
    var displayName: String {
        switch self {
        case .overview: "Overview"
        case .exposure: "Exposure"
        case .performance: "Performance"
        case .allAssets: "All Assets"
        case .allPositions: "All Positions"
        case .accounts: "Accounts"
        }
    }
}
