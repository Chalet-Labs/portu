import SwiftUI

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

            switch appState.syncStatus {
            case .idle:
                EmptyView()
            case .syncing:
                Label("Syncing", systemImage: "arrow.trianglehead.2.counterclockwise")
                    .foregroundStyle(.secondary)
            case .completedWithErrors(let failedAccounts):
                Label(
                    "\(failedAccounts.count) account\(failedAccounts.count == 1 ? "" : "s") failed",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            case .error(let message):
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }

            Spacer()

            if let lastUpdate = appState.lastPriceUpdate {
                Text("Updated \(lastUpdate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("CoinGecko")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
