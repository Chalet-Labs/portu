import SwiftUI
import PortuUI

struct AssetPricesPanel: View {
    let rows: [AssetPriceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Asset Prices",
                subtitle: "Top assets by latest value across the selected period"
            )

            if rows.isEmpty {
                emptyState("Sync asset snapshots with balances to compare price moves.")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    headerRow

                    ForEach(rows) { row in
                        GridRow {
                            Text(row.symbol)
                                .fontWeight(.medium)

                            Text(row.startPrice, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)

                            Text(row.endPrice, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)

                            changeLabel(
                                hasDefinedPercent: row.hasDefinedChangePercent,
                                percent: row.changePercent
                            )
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var headerRow: some View {
        GridRow {
            Text("Asset")
            Text("Start")
            Text("End")
            Text("Change")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func signedPercent(
        _ value: Decimal
    ) -> String {
        let prefix = value > .zero ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(2))))%"
    }

    @ViewBuilder
    private func changeLabel(
        hasDefinedPercent: Bool,
        percent: Decimal
    ) -> some View {
        if hasDefinedPercent {
            Text(signedPercent(percent))
                .foregroundStyle(changeColor(for: percent))
        } else {
            Text("New")
                .foregroundStyle(.secondary)
        }
    }

    private func changeColor(
        for value: Decimal
    ) -> Color {
        if value < .zero {
            return .red
        }

        if value > .zero {
            return .green
        }

        return .secondary
    }

    @ViewBuilder
    private func emptyState(
        _ message: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary.opacity(0.6))
            .frame(height: 220)
            .overlay {
                Text(message)
                    .foregroundStyle(.secondary)
            }
    }
}
