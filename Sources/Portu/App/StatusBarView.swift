import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

struct StatusBarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        HStack(spacing: 12) {
            if store.storeIsEphemeral {
                Label("Database error — using temporary storage", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(PortuTheme.dashboardWarning)
                    .font(.caption)
            }

            syncStatusLabel

            Spacer()

            if let lastUpdate = store.lastPriceUpdate {
                Text("Updated \(lastUpdate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }

            Text("CoinGecko")
                .font(.caption2)
                .foregroundStyle(PortuTheme.dashboardTertiaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(PortuTheme.dashboardPanelBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var syncStatusLabel: some View {
        switch store.syncStatus {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        case let .syncing(progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(PortuTheme.dashboardGold)
                Text("Syncing\u{2026}")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }
        case let .completedWithErrors(failed):
            Label("\(failed.count) account(s) failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardWarning)
                .help("Failed: \(failed.joined(separator: ", "))")
        case let .error(msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardWarning)
        }
    }
}
