// Sources/Portu/Features/AllAssets/NetworksTab.swift
import PortuCore
import SwiftData
import SwiftUI

struct NetworksTab: View {
    @Query private var allPositions: [Position]

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

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

        // Adjust for Decimal rounding so shares sum to exactly 1
        if totalValue != 0, !rows.isEmpty {
            let residual = 1 - rows.reduce(Decimal.zero) { $0 + $1.sharePercent }
            rows[0].sharePercent += residual
        }
        return rows
    }

    private var rows: [NetworkRow] {
        Self.computeRows(from: positions.map { (chain: $0.chain?.rawValue, netUSDValue: $0.netUSDValue) })
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
