// Sources/Portu/Features/Overview/OverviewTopBar.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]

    let onSync: () -> Void

    /// Only positions from active accounts
    private var activePositions: [Position] {
        positions.filter { $0.account?.isActive == true }
    }

    private var totalValue: Decimal {
        activePositions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
    }

    private var change24h: Decimal {
        // Sum: token.amount * priceChange24h for each token, sign-adjusted by role
        var total: Decimal = 0
        for pos in activePositions {
            for token in pos.tokens {
                guard
                    let asset = token.asset,
                    let cgId = asset.coinGeckoId,
                    let price = appState.prices[cgId],
                    let changePct = appState.priceChanges24h[cgId] else { continue }

                let contribution = token.amount * price * changePct
                if token.role.isPositive {
                    total += contribution
                } else if token.role.isBorrow {
                    total -= contribution
                }
                // reward: excluded
            }
        }
        return total
    }

    private var changePct: Decimal {
        let prev = totalValue - change24h
        guard prev != 0 else { return 0 }
        return change24h / prev
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Total value
            VStack(alignment: .leading, spacing: 2) {
                Text("Portfolio Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalValue, format: .currency(code: "USD"))
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }

            // 24h change
            VStack(alignment: .leading, spacing: 2) {
                Text("24h Change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(PortuTheme.changeColor(for: change24h))
                    Text(change24h, format: .currency(code: "USD"))
                        .foregroundStyle(PortuTheme.changeColor(for: change24h))
                    Text("(\(changePct, format: .percent.precision(.fractionLength(2))))")
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }

            Spacer()

            // Last synced + Sync button
            if case .syncing = appState.syncStatus {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: onSync) {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .padding()
    }
}
