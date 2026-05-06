// Sources/Portu/Features/Overview/OverviewSummaryCards.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

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
            ("Tokens & Memecoins", tokens)
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
            let posVal = pos.tokens.filter(\.role.isPositive).reduce(Decimal.zero) { $0 + $1.usdValue }
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
            ("Yield", yield)
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortuTheme.dashboardContentSpacing) {
            summaryCard(title: "Idle", items: idleBreakdown)
            summaryCard(title: "Deployed", items: deployedBreakdown)
            summaryCard(title: "Futures", items: []) // Future work
        }
    }

    private func summaryCard(title: String, items: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            if items.isEmpty {
                Text(OverviewSummaryCardText.emptyState(for: title))
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(items, id: \.0) { label, value in
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(value, format: .currency(code: "USD"))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(PortuTheme.dashboardText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .dashboardCard()
    }
}

enum OverviewSummaryCardText {
    static func emptyState(for title: String) -> String {
        title == "Futures" ? "Coming soon" : "No deployed positions"
    }
}
