import Foundation
import PortuCore

/// Centralizes price-source precedence (live > sync fallback > zero)
/// and role-aware sign logic for token values.
enum AssetValueFormatter {
    enum PriceSource: String {
        case live
        case syncFallback
    }

    private static let hundred = Decimal(100)

    static func priceSource(
        for token: PositionToken,
        livePrices: [String: Decimal]) -> PriceSource? {
        if livePrice(for: token, livePrices: livePrices) != nil {
            return .live
        }
        return fallbackPrice(for: token) == nil ? nil : .syncFallback
    }

    static func livePrice(
        for token: PositionToken,
        livePrices: [String: Decimal]) -> Decimal? {
        guard let coinGeckoId = token.asset?.coinGeckoId else { return nil }
        return livePrices[coinGeckoId]
    }

    static func fallbackPrice(for token: PositionToken) -> Decimal? {
        guard token.amount > .zero, token.usdValue >= .zero else { return nil }
        return token.usdValue / token.amount
    }

    /// Best available price: live CoinGecko price, or sync-time USD/amount ratio.
    static func displayPrice(
        for token: PositionToken,
        livePrices: [String: Decimal]) -> Decimal {
        livePrice(for: token, livePrices: livePrices)
            ?? fallbackPrice(for: token)
            ?? .zero
    }

    /// Best available USD value: live price * amount, or sync-time usdValue.
    static func displayValue(
        for token: PositionToken,
        livePrices: [String: Decimal]) -> Decimal {
        if let livePrice = livePrice(for: token, livePrices: livePrices) {
            return token.amount * livePrice
        }
        return token.usdValue
    }

    /// Role-aware signed value: borrows negative, rewards zero, everything else positive.
    static func signedValue(
        for token: PositionToken,
        livePrices: [String: Decimal]) -> Decimal {
        let absoluteValue = displayValue(for: token, livePrices: livePrices)
        return switch token.role {
        case .borrow: -absoluteValue
        case .reward: Decimal.zero
        case .balance, .supply, .stake, .lpToken: absoluteValue
        }
    }

    /// 24h change contribution from this token, accounting for role sign.
    static func changeContribution24h(
        for token: PositionToken,
        livePrices: [String: Decimal],
        changes24h: [String: Decimal]) -> Decimal {
        guard
            let coinGeckoId = token.asset?.coinGeckoId,
            let livePrice = livePrices[coinGeckoId],
            let changePercent = changes24h[coinGeckoId]
        else {
            return .zero
        }
        let absoluteChange = token.amount * livePrice * (changePercent / hundred)
        return switch token.role {
        case .borrow: -absoluteChange
        case .reward: Decimal.zero
        case .balance, .supply, .stake, .lpToken: absoluteChange
        }
    }
}
