import SwiftUI
import PortuCore
import PortuUI

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
