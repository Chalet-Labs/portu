import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct AssetPositionsTable: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Query private var allTokens: [PositionToken]

    private var rows: [PositionRowData] {
        let entries = PositionTokenEntry.fromActiveTokens(allTokens, assetId: assetId)
        return AssetDetailFeature.aggregatePositionRows(tokens: entries, prices: store.prices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions").font(.headline)

            Table(rows) {
                TableColumn("Account") { row in Text(row.accountName) }
                    .width(min: 80, ideal: 120)
                TableColumn("Platform") { row in Text(row.platformName) }
                    .width(min: 80, ideal: 100)
                TableColumn("Context") { row in
                    CapsuleBadge(row.context)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Network") { row in Text(row.network) }
                    .width(min: 60, ideal: 80)
                TableColumn("Amount") { row in
                    Text(row.amount, format: .number.precision(.fractionLength(2 ... 8)))
                }
                .width(min: 80, ideal: 100)
                TableColumn("USD Balance") { row in
                    Text(row.usdBalance, format: .currency(code: "USD"))
                }
                .width(min: 80, ideal: 100)
            }
        }
    }
}
