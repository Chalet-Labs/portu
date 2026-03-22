import SwiftUI
import PortuCore
import PortuUI

/// Shared holding row — used in both PortfolioView and AccountDetailView.
/// Includes full VoiceOver accessibility label per spec requirements.
struct HoldingRow: View {
    let position: Position
    let livePrices: [String: Decimal]

    private var primaryToken: PositionToken? {
        position.tokens.first
    }

    private var primaryAsset: Asset? {
        primaryToken?.asset
    }

    private var title: String {
        position.protocolName ?? primaryAsset?.symbol ?? position.positionType.rawValue.capitalized
    }

    private var subtitle: String {
        primaryAsset?.name ?? position.chain?.rawValue.capitalized ?? "Position"
    }

    private var amountDescription: String {
        guard let primaryToken, let symbol = primaryAsset?.symbol else {
            return "\(position.tokens.count) token\(position.tokens.count == 1 ? "" : "s")"
        }
        return "\(primaryToken.amount.formatted()) \(symbol)"
    }

    private var value: Decimal {
        guard let primaryToken,
              position.tokens.count == 1,
              let coinGeckoId = primaryAsset?.coinGeckoId,
              let livePrice = livePrices[coinGeckoId]
        else {
            return position.netUSDValue
        }

        let absoluteValue = primaryToken.amount * livePrice
        switch primaryToken.role {
        case .borrow:
            return -absoluteValue
        case .reward:
            return 0
        case .balance, .supply, .stake, .lpToken:
            return absoluteValue
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                CurrencyText(value)
                Text(amountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(subtitle), valued at \(value.formatted(.currency(code: "USD"))), amount \(amountDescription)"
        )
    }
}
