// Sources/Portu/Features/AllAssets/NetworksTab.swift
import PortuCore
import SwiftData
import SwiftUI

struct NetworksTab: View {
    @Query private var allPositions: [Position]

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    private struct NetworkRow: Identifiable {
        let id: String
        let name: String
        let sharePercent: Decimal
        let positionCount: Int
        let usdBalance: Decimal
    }

    private var rows: [NetworkRow] {
        let totalValue = positions.reduce(Decimal.zero) { $0 + max($1.netUSDValue, 0) }

        var byChain: [String: (count: Int, value: Decimal)] = [:]
        for pos in positions {
            let key = pos.chain?.rawValue ?? "__offchain__"
            var entry = byChain[key] ?? (0, 0)
            entry.count += 1
            entry.value += pos.netUSDValue
            byChain[key] = entry
        }

        return byChain.map { key, entry in
            NetworkRow(
                id: key,
                name: key == "__offchain__" ? "Off-chain / Custodial" : key.capitalized,
                sharePercent: totalValue > 0 ? entry.value / totalValue : 0,
                positionCount: entry.count,
                usdBalance: entry.value
            )
        }
        .sorted { $0.usdBalance > $1.usdBalance }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Network") { row in Text(row.name).fontWeight(.medium) }
            TableColumn("Share %") { row in
                Text(row.sharePercent, format: .percent.precision(.fractionLength(1)))
            }
            TableColumn("# Positions") { row in Text("\(row.positionCount)") }
            TableColumn("USD Balance") { row in
                Text(row.usdBalance, format: .currency(code: "USD"))
            }
        }
    }
}
