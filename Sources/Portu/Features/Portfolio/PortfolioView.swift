import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct PortfolioView: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]

    private var activePositions: [Position] {
        positions.filter { $0.account?.isActive ?? false }
    }

    private var totalValue: Decimal {
        activePositions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
    }

    var body: some View {
        Group {
            if activePositions.isEmpty {
                ContentUnavailableView {
                    Label("No Overview Data", systemImage: "chart.pie")
                } description: {
                    Text("Add an account or run a sync to populate positions.")
                } actions: {
                    Button("Add Account") {
                        // TODO: Add account flow
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SummaryCards(totalValue: totalValue, positionsCount: activePositions.count)
                        positionsList
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Overview")
    }

    /// Helper to create a P&L label with directional icon.
    /// Satisfies spec: "do not rely solely on green/red color for gain/loss"
    /// Expects a percentage-point value (e.g. 5.3 for +5.3%), matching CoinGecko's format.
    @ViewBuilder
    static func changeLabel(value: Decimal) -> some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
            Text("\(value.formatted(.number.precision(.fractionLength(2))))%")
        }
        .foregroundStyle(PortuTheme.changeColor(for: value))
        .accessibilityLabel(
            "\(value >= 0 ? "up" : "down") \(abs(value).formatted(.number.precision(.fractionLength(2))))%"
        )
    }

    @ViewBuilder
    private var positionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions")
                .font(.headline)

            ForEach(activePositions) { position in
                HoldingRow(position: position, livePrices: appState.prices)
            }
        }
    }
}
