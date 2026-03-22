// Sources/Portu/Features/Overview/OverviewSummaryCards.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct OverviewSummaryCards: View {
    @Query private var allPositions: [Position]

    /// Only positions from active accounts
    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    private var idleBreakdown: [(String, Decimal)] {
        let idle = positions.filter { $0.positionType == .idle }
        var stablesFiat: Decimal = 0
        var majors: Decimal = 0
        var tokens: Decimal = 0

        for pos in idle {
            for token in pos.tokens where token.role.isPositive {
                switch token.asset?.category {
                case .stablecoin, .fiat: stablesFiat += token.usdValue
                case .major: majors += token.usdValue
                default: tokens += token.usdValue
                }
            }
        }
        return [
            ("Stablecoins & Fiat", stablesFiat),
            ("Majors", majors),
            ("Tokens & Memes", tokens),
        ]
    }

    private var deployedBreakdown: [(String, Decimal)] {
        let deployed = positions.filter {
            [.lending, .staking, .farming, .liquidityPool].contains($0.positionType)
        }
        var lending: Decimal = 0
        var staked: Decimal = 0
        var yield: Decimal = 0

        for pos in deployed {
            let posVal = pos.tokens.filter { $0.role.isPositive }.reduce(Decimal.zero) { $0 + $1.usdValue }
            switch pos.positionType {
            case .lending: lending += posVal
            case .staking: staked += posVal
            case .farming, .liquidityPool: yield += posVal
            default: break
            }
        }
        return [
            ("Lending", lending),
            ("Staked", staked),
            ("Yield", yield),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            summaryCard(title: "Idle", items: idleBreakdown)
            summaryCard(title: "Deployed", items: deployedBreakdown)
            summaryCard(title: "Futures", items: []) // Future work
        }
    }

    private func summaryCard(title: String, items: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            let total = items.reduce(Decimal.zero) { $0 + $1.1 }
            Text(total, format: .currency(code: "USD"))
                .font(.title3.weight(.semibold))

            if items.isEmpty {
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items, id: \.0) { label, value in
                    HStack {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(value, format: .currency(code: "USD")).font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
