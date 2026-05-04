// Sources/Portu/Features/Overview/OverviewTopBar.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]

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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Portfolio value")
                    .font(DashboardStyle.labelFont)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                Text(totalValue, format: .currency(code: "USD"))
                    .font(DashboardStyle.heroValueFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(change24h < 0 ? "-" : "+")
                    Text(change24h, format: .currency(code: "USD"))
                    Spacer()
                    Text("$ change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                }
                .foregroundStyle(PortuTheme.changeColor(for: change24h))

                HStack(spacing: 4) {
                    Image(systemName: changePct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(changePct, format: .percent.precision(.fractionLength(2)))
                    Spacer()
                    Text("% change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                }
                .foregroundStyle(PortuTheme.changeColor(for: changePct))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}
