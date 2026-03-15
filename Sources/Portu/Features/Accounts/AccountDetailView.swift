import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct AccountDetailView: View {
    let accountID: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    private var account: Account? {
        try? modelContext.model(for: accountID) as? Account
    }

    var body: some View {
        Group {
            if let account {
                accountContent(account)
            } else {
                ContentUnavailableView(
                    "Account Not Found",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    @ViewBuilder
    private func accountContent(_ account: Account) -> some View {
        Group {
            if account.holdings.isEmpty {
                ContentUnavailableView {
                    Label("No Holdings", systemImage: "tray")
                } description: {
                    Text("This account has no holdings yet.")
                } actions: {
                    if account.kind == .exchange {
                        Button("Sync Account") {
                            // TODO: Sync from exchange
                        }
                    }
                }
            } else {
                List(account.holdings) { holding in
                    HoldingRow(
                        holding: holding,
                        price: appState.prices[holding.asset?.coinGeckoId ?? ""]
                    )
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem {
                if let lastSync = account.lastSyncedAt {
                    Text("Synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
