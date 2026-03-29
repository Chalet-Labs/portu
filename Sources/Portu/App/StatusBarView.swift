import ComposableArchitecture
import PortuCore
import SwiftUI

struct StatusBarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        HStack(spacing: 12) {
            if store.storeIsEphemeral {
                Label("Database error — using temporary storage", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            syncStatusLabel

            Spacer()

            if let lastUpdate = store.lastPriceUpdate {
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
        switch store.syncStatus {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .syncing(progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 60)
                Text("Syncing\u{2026}")
                    .font(.caption)
            }
        case let .completedWithErrors(failed):
            Label("\(failed.count) account(s) failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Failed: \(failed.joined(separator: ", "))")
        case let .error(msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
