import SwiftUI
import SwiftData
import PortuCore

struct AssetPositionsTable: View {
    let assetId: UUID

    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    private struct PositionRow: Identifiable {
        let id: UUID
        let accountName: String
        let platformName: String
        let context: String // Staked/Idle/Lending/etc.
        let network: String
        let amount: Decimal
        let usdBalance: Decimal
    }

    private var rows: [PositionRow] {
        allTokens
            .filter { $0.asset?.id == assetId }
            .compactMap { token -> PositionRow? in
                guard let pos = token.position else { return nil }
                let value = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
                    ?? token.usdValue

                return PositionRow(
                    id: token.id,
                    accountName: pos.account?.name ?? "Unknown",
                    platformName: pos.protocolName ?? "Wallet",
                    context: pos.positionType.rawValue.capitalized,
                    network: pos.chain?.rawValue.capitalized ?? "Off-chain",
                    amount: token.amount,
                    usdBalance: value
                )
            }
            .sorted { $0.usdBalance > $1.usdBalance }
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
                    Text(row.amount, format: .number.precision(.fractionLength(2...8)))
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
