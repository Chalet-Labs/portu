// Sources/Portu/Features/Positions/PositionGroupView.swift
import PortuCore
import PortuUI
import SwiftUI

struct PositionGroupView: View {
    let position: Position
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let name = position.protocolName {
                    Text(name).font(DashboardStyle.sectionTitleFont)
                } else {
                    Text(position.positionType.rawValue.capitalized).font(DashboardStyle.sectionTitleFont)
                }

                if let chain = position.chain {
                    CapsuleBadge(chain.rawValue.capitalized)
                }

                Spacer()

                if let hf = position.healthFactor {
                    Label("HF: \(hf, specifier: "%.2f")", systemImage: "heart.text.square")
                        .font(.caption)
                        .foregroundStyle(hf < 1.2 ? .red : hf < 1.5 ? .orange : .green)
                }

                // Net value (signed), computed from live prices to match token rows.
                let headerTotal = PositionGroupValue.headerTotal(
                    for: position.tokens,
                    livePrices: appState.prices)
                Text(headerTotal, format: .currency(code: "USD"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PortuTheme.changeColor(for: headerTotal))
            }

            ForEach(position.tokens, id: \.id) { token in
                HStack {
                    Text(token.role.displayLabel)
                        .font(.caption)
                        .foregroundStyle(token.role.displayColor)

                    Text(token.asset?.symbol ?? "???")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PortuTheme.dashboardText)

                    Spacer()

                    Text(token.amount, format: .number.precision(.fractionLength(2 ... 6)))
                        .font(DashboardStyle.monoTableFont)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)

                    let value = tokenValue(token)
                    Text(value, format: .currency(code: "USD"))
                        .font(DashboardStyle.monoTableFont)
                        .foregroundStyle(PortuTheme.dashboardText)
                        .frame(width: 100, alignment: .trailing)
                }
            }
        }
        .dashboardCard(horizontalPadding: 12, verticalPadding: 10)
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        token.resolvedUSDValue(prices: appState.prices)
    }
}

enum PositionGroupValue {
    static func headerTotal(
        for tokens: [PositionToken],
        livePrices: [String: Decimal]) -> Decimal {
        tokens.reduce(Decimal.zero) { total, token in
            total + AssetValueFormatter.signedValue(for: token, livePrices: livePrices)
        }
    }
}
