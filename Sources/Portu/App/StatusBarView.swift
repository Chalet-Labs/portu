import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            if appState.storeIsEphemeral {
                Label("Data not saved — database error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

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
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
