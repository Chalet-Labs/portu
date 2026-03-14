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
            case .portfolio:
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
                Button("Refresh", systemImage: "arrow.clockwise") {
                    // TODO: Trigger price refresh
                }
            }
        }
    }
}

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            switch appState.connectionStatus {
            case .idle:
                Label("Idle", systemImage: "circle")
                    .foregroundStyle(.secondary)
            case .fetching:
                Label("Updating...", systemImage: "arrow.trianglehead.2.counterclockwise")
                    .foregroundStyle(.secondary)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            Spacer()

            if let lastUpdate = appState.lastPriceUpdate {
                Text("Updated \(lastUpdate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("CoinGecko")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection
    @Query private var portfolios: [Portfolio]
    @Query(sort: \Account.name) private var accounts: [Account]

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Portfolio", systemImage: "chart.pie")
                    .tag(SidebarSection.portfolio)
            }

            Section("Accounts") {
                if accounts.isEmpty {
                    Text("No accounts yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: iconForAccount(account))
                            .tag(SidebarSection.account(account.persistentModelID))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Portu")
        .toolbar {
            ToolbarItem {
                Button("Add Account", systemImage: "plus") {
                    // TODO: Add account flow
                }
            }
        }
    }

    private func iconForAccount(_ account: Account) -> String {
        switch account.kind {
        case .manual: "tray"
        case .exchange: "building.columns"
        case .wallet: "wallet.bifold"
        }
    }
}
