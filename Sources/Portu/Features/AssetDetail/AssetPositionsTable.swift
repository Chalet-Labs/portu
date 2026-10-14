import PortuCore
import PortuUI
import SwiftUI

/// The asset's token rows (U4): a counted token shows its signed contribution, a not-counted one its
/// own value, muted and tagged; an unpriced one a caption and an ignored one a badge, neither with a
/// value. An ignored row is greyed.
struct AssetPositionsTable: View {
    let rows: [AssetPositionRow]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions")
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)

            Table(rows) {
                TableColumn("Account") { row in
                    Text(row.accountName).foregroundStyle(PortuTheme.dashboardText).greyedIfIgnored(row)
                }
                .width(min: 80, ideal: 120)
                TableColumn("Platform") { row in Text(row.platformName).greyedIfIgnored(row) }
                    .width(min: 80, ideal: 100)
                TableColumn("Context") { row in
                    CapsuleBadge(row.context).greyedIfIgnored(row)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Network") { row in Text(row.network).greyedIfIgnored(row) }
                    .width(min: 60, ideal: 80)
                TableColumn("Amount") { row in
                    Text(AssetDetailFormat.amount(row.amount))
                        .font(DashboardStyle.monoTableFont)
                        .greyedIfIgnored(row)
                }
                .width(min: 80, ideal: 100)
                TableColumn("Balance") { row in
                    AssetPositionBalanceCell(row: row, currencyCode: currencyCode)
                }
                .width(min: 80, ideal: 100)
            }
            .dashboardTable()
        }
    }
}

private struct AssetPositionBalanceCell: View {
    let row: AssetPositionRow
    let currencyCode: String

    var body: some View {
        HStack(spacing: 6) {
            switch row.state {
            case .ignored: CapsuleBadge(TokenRowLabels.ignored)
            case .notCounted: CapsuleBadge(TokenRowLabels.notCounted)
            case .counted, .unpriced: EmptyView()
            }

            if let value = row.value {
                Text(AssetDetailFormat.currency(value, code: currencyCode))
                    .font(DashboardStyle.monoTableFont)
                    .foregroundStyle(row.state == .counted ? PortuTheme.dashboardText : PortuTheme.dashboardTertiaryText)
            } else if row.state == .unpriced {
                Text(TokenRowLabels.unpriced)
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
            }
        }
        .greyedIfIgnored(row)
    }
}

private extension View {
    func greyedIfIgnored(_ row: AssetPositionRow) -> some View {
        opacity(row.state == .ignored ? 0.5 : 1)
    }
}
