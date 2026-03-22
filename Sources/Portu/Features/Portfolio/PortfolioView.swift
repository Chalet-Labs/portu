import SwiftUI
import SwiftData
import PortuCore
import PortuUI

/// Placeholder — PortfolioView will be rebuilt in Plan 02 with new data schema.
struct PortfolioView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ContentUnavailableView {
            Label("Portfolio", systemImage: "chart.pie")
        } description: {
            Text("Add an account or enter holdings manually to get started.")
        } actions: {
            Button("Add Account") {
                // TODO: Add account flow
            }
        }
        .navigationTitle("Portfolio")
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
}
