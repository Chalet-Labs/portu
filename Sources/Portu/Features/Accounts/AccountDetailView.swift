import SwiftUI
import SwiftData
import PortuCore
import PortuUI

/// Placeholder — AccountDetailView will be rebuilt in Plan 02 with Position-based views.
struct AccountDetailView: View {
    let accountID: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var account: Account?

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
        .task(id: accountID) {
            account = nil
            account = try? modelContext.model(for: accountID) as? Account
        }
    }

    @ViewBuilder
    private func accountContent(_ account: Account) -> some View {
        Group {
            if account.positions.isEmpty {
                ContentUnavailableView {
                    Label("No Positions", systemImage: "tray")
                } description: {
                    Text("This account has no positions yet.")
                } actions: {
                    if account.kind == .exchange {
                        Button("Sync Account") {
                            // TODO: Sync from exchange
                        }
                    }
                }
            } else {
                List(account.positions) { position in
                    Text(position.positionType.rawValue)
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
