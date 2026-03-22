import Foundation
import PortuCore

enum AssetValueFormatter {
    enum PriceSource: String, Sendable {
        case live
        case syncFallback
    }

    private static let hundred = Decimal(100)

    static func priceSource(
        for token: PositionToken,
        livePrices: [String: Decimal]
    ) -> PriceSource? {
        if livePrice(for: token, livePrices: livePrices) != nil {
            return .live
        }

        return fallbackPrice(for: token) == nil ? nil : .syncFallback
    }

    static func livePrice(
        for token: PositionToken,
        livePrices: [String: Decimal]
    ) -> Decimal? {
        guard let coinGeckoId = token.asset?.coinGeckoId else {
            return nil
        }

        return livePrices[coinGeckoId]
    }

    static func fallbackPrice(for token: PositionToken) -> Decimal? {
        guard token.amount != .zero else {
            return nil
        }

        return token.usdValue / token.amount
    }

    static func displayPrice(
        for token: PositionToken,
        livePrices: [String: Decimal]
    ) -> Decimal {
        livePrice(for: token, livePrices: livePrices)
            ?? fallbackPrice(for: token)
            ?? .zero
    }

    static func displayValue(
        for token: PositionToken,
        livePrices: [String: Decimal]
    ) -> Decimal {
        if let livePrice = livePrice(for: token, livePrices: livePrices) {
            return token.amount * livePrice
        }

        return token.usdValue
    }

    static func signedValue(
        for token: PositionToken,
        livePrices: [String: Decimal]
    ) -> Decimal {
        let absoluteValue = displayValue(for: token, livePrices: livePrices)

        switch token.role {
        case .borrow:
            return -absoluteValue
        case .reward:
            return Decimal.zero
        case .balance, .supply, .stake, .lpToken:
            return absoluteValue
        }
    }

    static func changeContribution24h(
        for token: PositionToken,
        livePrices: [String: Decimal],
        changes24h: [String: Decimal]
    ) -> Decimal {
        guard let coinGeckoId = token.asset?.coinGeckoId,
              let livePrice = livePrices[coinGeckoId],
              let changePercent = changes24h[coinGeckoId]
        else {
            return .zero
        }

        let absoluteChange = token.amount * livePrice * (changePercent / hundred)

        switch token.role {
        case .borrow:
            return -absoluteChange
        case .reward:
            return Decimal.zero
        case .balance, .supply, .stake, .lpToken:
            return absoluteChange
        }
    }

    static func roleLabel(for role: TokenRole) -> String {
        switch role {
        case .balance:
            return "Balance"
        case .supply:
            return "Supply"
        case .borrow:
            return "Borrow"
        case .reward:
            return "Reward"
        case .stake:
            return "Stake"
        case .lpToken:
            return "LP"
        }
    }
}
