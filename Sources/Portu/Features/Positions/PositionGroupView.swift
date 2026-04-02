// Sources/Portu/Features/Positions/PositionGroupView.swift
import PortuCore
import PortuUI
import SwiftUI

struct PositionGroupView: View {
    let position: Position
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: protocol name, chain, health factor
            HStack {
                if let name = position.protocolName {
                    Text(name).font(.headline)
                } else {
                    Text(position.positionType.rawValue.capitalized).font(.headline)
                }

                if let chain = position.chain {
                    Text(chain.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Spacer()

                if let hf = position.healthFactor {
                    Label("HF: \(hf, specifier: "%.2f")", systemImage: "heart.text.square")
                        .font(.caption)
                        .foregroundStyle(hf < 1.2 ? .red : hf < 1.5 ? .orange : .green)
                }

                // Net value (signed)
                Text(position.netUSDValue, format: .currency(code: "USD"))
                    .font(.headline)
                    .foregroundStyle(PortuTheme.changeColor(for: position.netUSDValue))
            }

            // Token rows
            ForEach(position.tokens, id: \.id) { token in
                HStack {
                    Text(token.role.displayLabel)
                        .font(.caption)
                        .foregroundStyle(token.role.displayColor)

                    Text(token.asset?.symbol ?? "???")
                        .fontWeight(.medium)

                    Spacer()

                    Text(token.amount, format: .number.precision(.fractionLength(2 ... 6)))
                        .foregroundStyle(.secondary)

                    // Always positive display
                    let value = tokenValue(token)
                    Text(value, format: .currency(code: "USD"))
                        .frame(width: 100, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        token.resolvedUSDValue(prices: appState.prices)
    }
}
