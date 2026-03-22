import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            if appState.storeIsEphemeral {
                Label("Data not saved — database error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            switch appState.syncStatus {
            case .idle:
                Label("Ready", systemImage: "circle")
                    .foregroundStyle(.secondary)
            case .syncing(let progress):
                Label("Syncing \(Int(progress * 100))%", systemImage: "arrow.trianglehead.2.counterclockwise")
                    .foregroundStyle(.secondary)
            case .completedWithErrors(let failed):
                Label("\(failed.count) account(s) failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
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
