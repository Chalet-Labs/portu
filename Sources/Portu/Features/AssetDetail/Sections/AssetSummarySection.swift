import SwiftUI
import PortuUI

struct AssetSummarySection: View {
    let accountCount: Int
    let totalAmount: Decimal
    let totalUSDValue: Decimal
    let networkRows: [AssetHoldingSummaryRow]
    let containsPartialHistory: Bool

    private let statColumns = [
        GridItem(.flexible(minimum: 120), spacing: 12),
        GridItem(.flexible(minimum: 120), spacing: 12),
        GridItem(.flexible(minimum: 120), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Holdings Summary",
                subtitle: "All accounts, net balances, and network distribution"
            )

            LazyVGrid(columns: statColumns, alignment: .leading, spacing: 12) {
                StatCard(
                    title: "All Accounts",
                    value: "\(accountCount)"
                )

                StatCard(
                    title: "Net Amount",
                    value: totalAmount.formatted(),
                    subtitle: totalAmount < .zero ? "Borrowed across active positions" : "Held across active positions",
                    valueColor: totalAmount < .zero ? .red : nil
                )

                StatCard(
                    title: "Net USD Value",
                    value: totalUSDValue.formatted(.currency(code: "USD")),
                    subtitle: totalUSDValue < .zero ? "Debt after borrows" : "Balance after borrows",
                    valueColor: totalUSDValue < .zero ? .red : nil
                )
            }

            if containsPartialHistory {
                Label("History includes one or more partial sync batches.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    "On Networks",
                    subtitle: "Grouped by the position chain that currently holds this asset"
                )

                if networkRows.isEmpty {
                    ContentUnavailableView {
                        Label("No Networks", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text("Sync positions with this asset to populate the network summary.")
                    }
                    .frame(minHeight: 180)
                } else {
                    Table(networkRows) {
                        TableColumn("Network") { row in
                            Text(row.networkName)
                        }
                        TableColumn("Amount") { row in
                            Text(row.amount.formatted())
                        }
                        TableColumn("Share") { row in
                            Text(shareLabel(for: row.share))
                        }
                        TableColumn("USD Value") { row in
                            CurrencyText(row.usdValue)
                        }
                    }
                    .frame(minHeight: tableHeight(for: networkRows.count))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func shareLabel(
        for share: Decimal
    ) -> String {
        "\(share.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func tableHeight(
        for rowCount: Int
    ) -> CGFloat {
        max(180, CGFloat(rowCount) * 44)
    }
}
