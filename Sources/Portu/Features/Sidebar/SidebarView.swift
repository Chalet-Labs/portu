import SwiftUI
import SwiftData
import PortuCore

struct SidebarView: View {
    @Binding var selection: SidebarSection
    // Single-portfolio MVP: loads all accounts unfiltered. When multi-portfolio
    // support is added, scope this query via a portfolio predicate.
    @Query(sort: \Account.name) private var accounts: [Account]

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Overview", systemImage: "chart.pie")
                    .tag(SidebarSection.overview)
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
