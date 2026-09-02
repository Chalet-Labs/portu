import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PlatformsTab: View {
    @Environment(AppState.self) private var appState
    @Query private var allPositions: [Position]

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    struct PlatformInput {
        let chain: String?
        let protocolId: String?
        let protocolName: String?
        let positionType: PositionType
        let netValue: Decimal
    }

    struct PlatformRow: Identifiable {
        let id: String // protocolId or sentinel
        let name: String
        var sharePercent: Decimal
        let networkCount: Int
        let positionCount: Int
        let balance: Decimal
    }

    nonisolated static func computeRows(from positions: [PlatformInput]) -> [PlatformRow] {
        let totalValue = positions.reduce(Decimal.zero) { $0 + $1.netValue }

        var byProtocol: [String: (name: String, chains: Set<String>, count: Int, value: Decimal)] = [:]

        for pos in positions {
            let key = pos.protocolId ?? (pos.positionType == .idle ? "__idle__" : "__unknown__")
            let name = pos.protocolName ?? (pos.positionType == .idle ? "Idle / Wallet" : "Unknown")
            var entry = byProtocol[key] ?? (name, [], 0, 0)
            entry.count += 1
            entry.value += pos.netValue
            if let chain = pos.chain {
                entry.chains.insert(chain)
            } else {
                entry.chains.insert("off-chain")
            }
            byProtocol[key] = entry
        }

        var rows = byProtocol.map { key, entry in
            PlatformRow(
                id: key,
                name: entry.name,
                sharePercent: totalValue != 0 ? entry.value / totalValue : 0,
                networkCount: entry.chains.count,
                positionCount: entry.count,
                balance: entry.value)
        }
        .sorted { $0.balance > $1.balance }

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
                    abs(rows[$0].balance) < abs(rows[$1].balance)
                }) {
                rows[idx].sharePercent += residual
            }
        }
        return rows
    }

    private var rows: [PlatformRow] {
        Self.computeRows(from: positions.map {
            PlatformInput(
                chain: $0.chain?.rawValue,
                protocolId: $0.protocolId,
                protocolName: $0.protocolName,
                positionType: $0.positionType,
                netValue: $0.netUSDValue * appState.currentUSDToDisplayRate)
        })
    }

    private var currencyCode: String {
        appState.currencyCode
    }

    var body: some View {
        Table(rows) {
            TableColumn("Platform") { row in Text(row.name).fontWeight(.medium).foregroundStyle(PortuTheme.dashboardText) }
            TableColumn("Share %") { row in
                Text(row.sharePercent, format: .percent.precision(.fractionLength(1)))
                    .font(DashboardStyle.monoTableFont)
            }
            TableColumn("# Networks") { row in Text("\(row.networkCount)") }
            TableColumn("# Positions") { row in Text("\(row.positionCount)") }
            TableColumn("Balance") { row in
                Text(row.balance, format: .currency(code: currencyCode))
                    .font(DashboardStyle.monoTableFont)
            }
        }
        .dashboardTable()
    }
}
