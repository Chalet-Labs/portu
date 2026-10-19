import PortuCore
import PortuUI
import SwiftUI

struct PositionGroupView: View {
    let card: AllPositionsCard
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.title).font(DashboardStyle.sectionTitleFont)

                if let chain = card.chain {
                    CapsuleBadge(chain.rawValue.capitalized)
                }

                Spacer()

                if let hf = card.healthFactor {
                    Label("HF: \(hf, specifier: "%.2f")", systemImage: "heart.text.square")
                        .font(.caption)
                        .foregroundStyle(hf < 1.2 ? .red : hf < 1.5 ? .orange : .green)
                }

                Text(AllPositionsFormat.currency(card.total, code: currencyCode))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PortuTheme.changeColor(for: card.total))
            }

            ForEach(card.rows) { row in
                PositionTokenRowView(row: row, currencyCode: currencyCode)
            }
        }
        .dashboardCard(horizontalPadding: 12, verticalPadding: 10)
    }
}

/// A token row (U4): a counted token shows its signed contribution, a not-counted one its own value,
/// muted and tagged; an unpriced one a caption and an ignored one a badge, neither with a value.
struct PositionTokenRowView: View {
    let row: AllPositionsRow
    let currencyCode: String

    var body: some View {
        HStack {
            Text(row.role.displayLabel)
                .font(.caption)
                .foregroundStyle(row.role.displayColor)

            Text(row.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(PortuTheme.dashboardText)

            switch row.state {
            case .ignored: CapsuleBadge(TokenRowLabels.ignored)
            case .notCounted: CapsuleBadge(TokenRowLabels.notCounted)
            case .counted, .unpriced: EmptyView()
            }

            Spacer()

            Text(AllPositionsFormat.amount(row.amount))
                .font(DashboardStyle.monoTableFont)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)

            Group {
                if let value = row.value {
                    Text(AllPositionsFormat.currency(value, code: currencyCode))
                        .font(DashboardStyle.monoTableFont)
                        .foregroundStyle(row.state == .counted ? PortuTheme.dashboardText : PortuTheme.dashboardTertiaryText)
                } else if row.state == .unpriced {
                    Text(TokenRowLabels.unpriced)
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 100, alignment: .trailing)
        }
        .opacity(row.state == .ignored ? 0.5 : 1)
    }
}
