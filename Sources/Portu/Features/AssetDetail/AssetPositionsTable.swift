import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct AssetPositionsTable: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Query private var allTokens: [PositionToken]

    private var rows: [PositionRowData] {
        let entries = allTokens
            .filter { $0.asset?.id == assetId && $0.position?.account?.isActive == true }
            .compactMap { token -> PositionTokenEntry? in
                guard let pos = token.position else { return nil }
                return PositionTokenEntry(
                    tokenId: token.id,
                    accountName: pos.account?.name ?? "Unknown",
                    protocolName: pos.protocolName,
                    positionType: pos.positionType,
                    chain: pos.chain,
                    role: token.role,
                    amount: token.amount,
                    usdValue: token.usdValue,
                    coinGeckoId: token.asset?.coinGeckoId)
            }
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
                    Text(row.context)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
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
