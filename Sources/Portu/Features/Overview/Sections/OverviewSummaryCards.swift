import SwiftUI
import PortuCore
import PortuUI

struct OverviewSummaryCards: View {
    struct Breakdown: Identifiable, Equatable {
        let id: String
        let title: String
        let value: Decimal
    }

    let positions: [Position]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Allocation",
                subtitle: "Idle balances, deployed capital, and future derivatives coverage"
            )

            HStack(spacing: 12) {
                StatCard(
                    title: "Idle",
                    value: idleValue.formatted(.currency(code: "USD")),
                    subtitle: "By asset category",
                    detailLines: detailLines(for: idleBreakdowns)
                )
                StatCard(
                    title: "Deployed",
                    value: deployedValue.formatted(.currency(code: "USD")),
                    subtitle: "By deployed strategy",
                    detailLines: detailLines(for: deployedBreakdowns)
                )
                StatCard(
                    title: "Futures",
                    value: Decimal.zero.formatted(.currency(code: "USD")),
                    subtitle: "Coming soon"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func idleBreakdown(for positions: [Position]) -> [Breakdown] {
        var values = Dictionary(
            uniqueKeysWithValues: IdleBreakdownGroup.allCases.map { ($0, Decimal.zero) }
        )

        for position in positions where position.positionType == .idle {
            for token in position.tokens where token.role != .reward && token.role != .borrow {
                let assetCategory = token.asset?.category ?? .other
                let group = IdleBreakdownGroup.group(for: assetCategory)
                values[group, default: .zero] += token.usdValue
            }
        }

        return IdleBreakdownGroup.allCases.map { group in
            Breakdown(id: group.title, title: group.title, value: values[group, default: .zero])
        }
    }

    static func deployedBreakdown(for positions: [Position]) -> [Breakdown] {
        var values = Dictionary(
            uniqueKeysWithValues: DeployedBreakdownGroup.allCases.map { ($0, Decimal.zero) }
        )

        for position in positions {
            guard let group = DeployedBreakdownGroup.group(for: position.positionType) else {
                continue
            }
            values[group, default: .zero] += position.netUSDValue
        }

        return DeployedBreakdownGroup.allCases.map { group in
            Breakdown(id: group.title, title: group.title, value: values[group, default: .zero])
        }
    }

    private var idleValue: Decimal {
        positions
            .filter { $0.positionType == .idle }
            .reduce(.zero) { $0 + $1.netUSDValue }
    }

    private var deployedValue: Decimal {
        positions
            .filter {
                switch $0.positionType {
                case .lending, .staking, .farming, .liquidityPool:
                    true
                case .idle, .vesting, .other:
                    false
                }
            }
            .reduce(.zero) { $0 + $1.netUSDValue }
    }

    private var idleBreakdowns: [Breakdown] {
        Self.idleBreakdown(for: positions)
    }

    private var deployedBreakdowns: [Breakdown] {
        Self.deployedBreakdown(for: positions)
    }

    private func detailLines(for breakdowns: [Breakdown]) -> [String] {
        breakdowns.map { breakdown in
            "\(breakdown.title): \(breakdown.value.formatted(.currency(code: "USD")))"
        }
    }
}

private enum IdleBreakdownGroup: CaseIterable, Hashable {
    case stablecoinsAndFiat
    case majors
    case tokensAndMemecoins

    var title: String {
        switch self {
        case .stablecoinsAndFiat:
            return "Stablecoins & Fiat"
        case .majors:
            return "Majors"
        case .tokensAndMemecoins:
            return "Tokens & Memecoins"
        }
    }

    static func group(for category: AssetCategory) -> IdleBreakdownGroup {
        switch category {
        case .stablecoin, .fiat:
            return .stablecoinsAndFiat
        case .major:
            return .majors
        case .defi, .meme, .privacy, .governance, .other:
            return .tokensAndMemecoins
        }
    }
}

private enum DeployedBreakdownGroup: CaseIterable, Hashable {
    case lending
    case staked
    case yield

    var title: String {
        switch self {
        case .lending:
            return "Lending"
        case .staked:
            return "Staked"
        case .yield:
            return "Yield"
        }
    }

    static func group(for positionType: PositionType) -> DeployedBreakdownGroup? {
        switch positionType {
        case .lending:
            return .lending
        case .staking:
            return .staked
        case .farming, .liquidityPool:
            return .yield
        case .idle, .vesting, .other:
            return nil
        }
    }
}
