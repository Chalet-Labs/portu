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
                        summaryCards
                        holdingsList
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Portfolio")
    }

    @ViewBuilder
    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total Value",
                value: totalValue.formatted(.currency(code: "USD"))
            )
            // P&L stub — directional icon pattern for accessibility
            StatCard(
                title: "24h Change",
                value: "--",
                subtitle: "No price history yet"
            )
            .accessibilityLabel("24 hour change, no data available")
            StatCard(
                title: "Holdings",
                value: "\(holdings.count)"
            )
        }
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

/// Shared holding row — used in both PortfolioView and AccountDetailView.
/// Includes full VoiceOver accessibility label per spec requirements.
struct HoldingRow: View {
    let holding: Holding
    let price: Decimal?

    private var value: Decimal {
        holding.amount * (price ?? 0)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(holding.asset?.symbol ?? "???")
                    .font(.headline)
                Text(holding.asset?.name ?? "Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                CurrencyText(value)
                Text("\(holding.amount.formatted()) \(holding.asset?.symbol ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(holding.asset?.name ?? "Unknown"), valued at \(value.formatted(.currency(code: "USD"))), amount \(holding.amount.formatted())"
        )
    }
}
