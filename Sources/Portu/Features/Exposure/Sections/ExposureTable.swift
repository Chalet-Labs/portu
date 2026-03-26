import SwiftUI
import PortuUI

struct ExposureTable: View {
    let rows: [ExposureRow]
    let displayMode: ExposureDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                displayMode == .category ? "Exposure by Category" : "Exposure by Asset",
                subtitle: "Spot assets, liabilities, and net exposure in one canonical view"
            )

            Table(rows) {
                TableColumn(displayMode == .category ? "Category" : "Asset") { row in
                    leadingCell(for: row)
                }
                TableColumn("Spot Assets") { row in
                    CurrencyText(row.spotAssets)
                }
                TableColumn("Liabilities") { row in
                    CurrencyText(row.liabilities)
                }
                TableColumn("Spot Net") { row in
                    CurrencyText(row.spotNet)
                }
                TableColumn("Long") { row in
                    CurrencyText(row.derivativesLong)
                }
                TableColumn("Short") { row in
                    CurrencyText(row.derivativesShort)
                }
                TableColumn("Net Exposure") { row in
                    CurrencyText(row.netExposure)
                }
            }
            .frame(minHeight: 280)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func leadingCell(
        for row: ExposureRow
    ) -> some View {
        if displayMode == .asset, let assetSymbol = row.assetSymbol {
            VStack(alignment: .leading, spacing: 2) {
                Text(assetSymbol)
                    .fontWeight(.medium)

                if row.name != assetSymbol {
                    Text(row.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(row.name)
                .fontWeight(.medium)
        }
    }
}
