import SwiftUI
import PortuUI

struct SummaryCards: View {
    let totalValue: Decimal
    let holdingsCount: Int

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total Value",
                value: totalValue.formatted(.currency(code: "USD"))
            )
            StatCard(
                title: "24h Change",
                value: "--",
                subtitle: "No price history yet"
            )
            .accessibilityLabel("24 hour change, no data available")
            StatCard(
                title: "Holdings",
                value: "\(holdingsCount)"
            )
        }
    }
}
