import SwiftUI
import PortuUI

struct PlatformsTabView: View {
    static let tableColumnTitles = ["Platform", "Share %", "# Networks", "# Positions", "USD Balance"]

    let rows: [PlatformTableRow]

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Platforms", systemImage: "building.columns")
                } description: {
                    Text("Sync more on-chain accounts to populate platform summaries.")
                }
            } else {
                Table(rows) {
                    TableColumn(Self.tableColumnTitles[0], value: \.name)
                    TableColumn(Self.tableColumnTitles[1]) { row in
                        Text(shareText(for: row.share))
                    }
                    TableColumn(Self.tableColumnTitles[2]) { row in
                        Text("\(row.networkCount)")
                    }
                    TableColumn(Self.tableColumnTitles[3]) { row in
                        Text("\(row.positionCount)")
                    }
                    TableColumn(Self.tableColumnTitles[4]) { row in
                        CurrencyText(row.usdBalance)
                    }
                }
            }
        }
        .padding()
    }

    private func shareText(
        for share: Decimal
    ) -> String {
        "\(share.formatted(.number.precision(.fractionLength(1))))%"
    }
}
