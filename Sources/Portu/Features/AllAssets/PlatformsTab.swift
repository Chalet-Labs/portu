// Sources/Portu/Features/AllAssets/PlatformsTab.swift
import PortuCore
import SwiftData
import SwiftUI

struct PlatformsTab: View {
    @Query private var allPositions: [Position]

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    private struct PlatformRow: Identifiable {
        let id: String // protocolId or sentinel
        let name: String
        let sharePercent: Decimal
        let networkCount: Int
        let positionCount: Int
        let usdBalance: Decimal
    }

    private var rows: [PlatformRow] {
        let totalValue = positions.reduce(Decimal.zero) { $0 + max($1.netUSDValue, 0) }

        var byProtocol: [String: (name: String, chains: Set<String>, count: Int, value: Decimal)] = [:]

        for pos in positions {
            let key = pos.protocolId ?? (pos.positionType == .idle ? "__idle__" : "__unknown__")
            let name = pos.protocolName ?? (pos.positionType == .idle ? "Idle / Wallet" : "Unknown")
            var entry = byProtocol[key] ?? (name, [], 0, 0)
            entry.count += 1
            entry.value += pos.netUSDValue
            if let chain = pos.chain { entry.chains.insert(chain.rawValue) } else { entry.chains.insert("off-chain") }
            byProtocol[key] = entry
        }

        return byProtocol.map { key, entry in
            PlatformRow(
                id: key,
                name: entry.name,
                sharePercent: totalValue > 0 ? entry.value / totalValue : 0,
                networkCount: entry.chains.count,
                positionCount: entry.count,
                usdBalance: entry.value)
        }
        .sorted { $0.usdBalance > $1.usdBalance }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Platform") { row in Text(row.name).fontWeight(.medium) }
            TableColumn("Share %") { row in
                Text(row.sharePercent, format: .percent.precision(.fractionLength(1)))
            }
            TableColumn("# Networks") { row in Text("\(row.networkCount)") }
            TableColumn("# Positions") { row in Text("\(row.positionCount)") }
            TableColumn("USD Balance") { row in
                Text(row.usdBalance, format: .currency(code: "USD"))
            }
        }
    }
}
