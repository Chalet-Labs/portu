import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct NetworksTab: View {
    @Environment(AppState.self) private var appState
    var sources = ValuationSources()
    @Query private var allTokens: [PositionToken]

    struct NetworkRow: Identifiable {
        let id: String
        let name: String
        var sharePercent: Decimal
        let positionCount: Int
        let usdBalance: Decimal
    }

    nonisolated static func computeRows(
        from positions: [(chain: String?, netUSDValue: Decimal)]) -> [NetworkRow] {
        let totalValue = positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }

        var byChain: [String: (count: Int, value: Decimal)] = [:]
        for pos in positions {
            let key = pos.chain ?? "__offchain__"
            var entry = byChain[key] ?? (0, 0)
            entry.count += 1
            entry.value += pos.netUSDValue
            byChain[key] = entry
        }

        var rows = byChain.map { key, entry in
            NetworkRow(
                id: key,
                name: key == "__offchain__" ? "Off-chain / Custodial" : key.capitalized,
                sharePercent: totalValue != 0 ? entry.value / totalValue : 0,
                positionCount: entry.count,
                usdBalance: entry.value)
        }
        .sorted { $0.usdBalance > $1.usdBalance }

        // Round to display precision (0.1% → 3 decimal places) then adjust residual
        // so the formatted percentages always sum to exactly 100.0%
        if totalValue != 0, !rows.isEmpty {
            for i in rows.indices {
                var rounded = Decimal()
                NSDecimalRound(&rounded, &rows[i].sharePercent, 3, .plain)
                rows[i].sharePercent = rounded
            }
            let residual = 1 - rows.reduce(Decimal.zero) { $0 + $1.sharePercent }
            if
                residual != 0,
                let idx = rows.indices.max(by: {
                    abs(rows[$0].usdBalance) < abs(rows[$1].usdBalance)
                }) {
                rows[idx].sharePercent += residual
            }
        }
        return rows
    }

    private var currencyCode: String {
        appState.currencyCode
    }

    var body: some View {
        let data = AllAssetsFeature.networks(sources.allAssets(allTokens).context)
        Table(data.entries) {
            TableColumn("Network") { entry in
                switch entry {
                case let .row(row):
                    Text(row.name).fontWeight(.medium).foregroundStyle(PortuTheme.dashboardText)
                case let .hidden(line):
                    Text(line.title).foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
            TableColumn("Share %") { entry in
                Text(AllAssetsFormat.share(entry.row?.share ?? entry.hidden?.share))
                    .font(DashboardStyle.monoTableFont)
            }
            TableColumn("# Positions") { entry in Text(entry.row.map { "\($0.positionCount)" } ?? "") }
            TableColumn("Balance") { entry in
                Text(entry.row?.balance ?? entry.hidden?.value ?? 0, format: .currency(code: currencyCode))
                    .font(DashboardStyle.monoTableFont)
            }
        }
        .dashboardTable()
    }
}
