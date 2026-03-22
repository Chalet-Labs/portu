import SwiftUI
import PortuCore
import PortuUI

struct OverviewTabbedTokens: View {
    struct BorrowingGroup: Identifiable, Sendable {
        let id: UUID
        let protocolName: String
        let chainLabel: String
        let accountName: String
        let healthFactor: Double?
        let rows: [OverviewTokenRow]

        var subtitle: String {
            let location = "\(chainLabel) / \(accountName)"
            guard let healthFactor else {
                return location
            }

            return "\(location) • Health \(healthFactor.formatted(.number.precision(.fractionLength(2))))"
        }
    }

    let viewModel: OverviewViewModel
    @State private var selectedTab: OverviewTab = .keyChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Token Breakdown",
                subtitle: "Position-token rows across key changes, idle holdings, and debt positions"
            )

            Picker("Overview Tab", selection: $selectedTab) {
                ForEach(OverviewTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedTab == .borrowing {
                borrowingSections
            } else {
                tokenRows(viewModel.rows(for: selectedTab))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var borrowingSections: some View {
        let groups = Self.makeBorrowingGroups(from: viewModel.rows(for: .borrowing))

        if groups.isEmpty {
            Text("No borrowing positions yet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.protocolName)
                                .font(.headline)
                            Text(group.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        tokenRows(group.rows, showRolePrefix: true)
                    }
                }
            }
        }
    }

    static func makeBorrowingGroups(from rows: [OverviewTokenRow]) -> [BorrowingGroup] {
        Dictionary(grouping: rows, by: \.positionID)
            .values
            .map { groupedRows in
                let sortedRows = groupedRows.sorted(by: compareBorrowingRows)
                let firstRow = sortedRows[0]

                return BorrowingGroup(
                    id: firstRow.positionID,
                    protocolName: firstRow.protocolName,
                    chainLabel: firstRow.chainLabel,
                    accountName: firstRow.accountName,
                    healthFactor: firstRow.healthFactor,
                    rows: sortedRows
                )
            }
            .sorted(by: compareBorrowingGroups)
    }

    @ViewBuilder
    private func tokenRows(
        _ rows: [OverviewTokenRow],
        showRolePrefix: Bool = false
    ) -> some View {
        if rows.isEmpty {
            Text("No tokens available for this tab.")
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    tokenRow(row, showRolePrefix: showRolePrefix)

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func tokenRow(
        _ row: OverviewTokenRow,
        showRolePrefix: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(showRolePrefix ? "\(rolePrefix(for: row.role)) \(row.symbol)" : row.symbol)
                    .font(.headline)
                Text(row.networkAccountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showRolePrefix {
                    Text(row.roleLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(row.amount.formatted()) \(row.symbol)")
                    .font(.subheadline.weight(.medium))
                Text(row.displayPrice.formatted(.currency(code: "USD")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CurrencyText(row.displayValue)
                    .font(.headline)
            }
        }
    }

    private static func compareBorrowingGroups(
        _ lhs: BorrowingGroup,
        _ rhs: BorrowingGroup
    ) -> Bool {
        if lhs.protocolName != rhs.protocolName {
            return lhs.protocolName < rhs.protocolName
        }

        if lhs.chainLabel != rhs.chainLabel {
            return lhs.chainLabel < rhs.chainLabel
        }

        if lhs.accountName != rhs.accountName {
            return lhs.accountName < rhs.accountName
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func compareBorrowingRows(
        _ lhs: OverviewTokenRow,
        _ rhs: OverviewTokenRow
    ) -> Bool {
        let lhsPriority = borrowingPriority(for: lhs.role)
        let rhsPriority = borrowingPriority(for: rhs.role)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.displayValue > rhs.displayValue
    }

    private static func borrowingPriority(for role: TokenRole) -> Int {
        switch role {
        case .borrow:
            return 0
        case .supply:
            return 1
        case .balance:
            return 2
        case .stake:
            return 3
        case .lpToken:
            return 4
        case .reward:
            return 5
        }
    }

    private func rolePrefix(for role: TokenRole) -> String {
        switch role {
        case .borrow:
            return "<- Borrow"
        case .supply:
            return "-> Supply"
        case .balance:
            return "Balance"
        case .stake:
            return "Stake"
        case .lpToken:
            return "LP"
        case .reward:
            return "Reward"
        }
    }
}
