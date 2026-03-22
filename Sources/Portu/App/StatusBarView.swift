import SwiftUI
import PortuCore

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            if appState.storeIsEphemeral {
                Label("Database error — using temporary storage", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            syncStatusLabel

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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var syncStatusLabel: some View {
        switch appState.syncStatus {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .syncing(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 60)
                Text("Syncing…")
                    .font(.caption)
            }
        case .completedWithErrors(let failed):
            Label("\(failed.count) account(s) failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Failed: \(failed.joined(separator: ", "))")
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
