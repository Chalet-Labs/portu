import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct PortfolioView: View {
    @Environment(AppState.self) private var appState
    @Query private var holdings: [Holding]

    private var totalValue: Decimal {
        holdings.reduce(Decimal.zero) { sum, holding in
            let coinId = holding.asset?.coinGeckoId ?? ""
            let price = appState.prices[coinId] ?? 0
            return sum + holding.amount * price
        }
    }

    var body: some View {
        Group {
            if holdings.isEmpty {
                ContentUnavailableView {
                    Label("No Portfolio", systemImage: "chart.pie")
                } description: {
                    Text("Add an account or enter holdings manually to get started.")
                } actions: {
                    Button("Add Account") {
                        // TODO: Add account flow
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SummaryCards(totalValue: totalValue, holdingsCount: holdings.count)
                        holdingsList
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Portfolio")
    }

    /// Helper to create a P&L label with directional icon.
    /// Satisfies spec: "do not rely solely on green/red color for gain/loss"
    @ViewBuilder
    static func changeLabel(value: Decimal) -> some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
            Text(value, format: .percent)
        }
        .foregroundStyle(PortuTheme.changeColor(for: value))
        .accessibilityLabel(
            "\(value >= 0 ? "up" : "down") \(abs(value).formatted(.percent))"
        )
    }

    @ViewBuilder
    private var holdingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Holdings")
                .font(.headline)

            ForEach(holdings) { holding in
                HoldingRow(holding: holding, price: appState.prices[holding.asset?.coinGeckoId ?? ""])
            }
        }
    }
}
