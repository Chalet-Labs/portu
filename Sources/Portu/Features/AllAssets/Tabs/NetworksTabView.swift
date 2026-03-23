import SwiftUI
import PortuUI

struct NetworksTabView: View {
    static let tableColumnTitles = ["Network", "Share %", "# Positions", "USD Balance"]

    let rows: [NetworkTableRow]

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Networks", systemImage: "globe")
                } description: {
                    Text("Sync more accounts to populate network summaries.")
                }
            } else {
                Table(rows) {
                    TableColumn(Self.tableColumnTitles[0], value: \.title)
                    TableColumn(Self.tableColumnTitles[1]) { row in
                        Text(shareText(for: row.share))
                    }
                    TableColumn(Self.tableColumnTitles[2]) { row in
                        Text("\(row.positionCount)")
                    }
                    TableColumn(Self.tableColumnTitles[3]) { row in
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
