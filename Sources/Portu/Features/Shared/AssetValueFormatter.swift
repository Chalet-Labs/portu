import Foundation
import PortuCore

/// Centralizes price-source precedence (live > sync fallback > zero)
/// and role-aware sign logic for token values.
enum AssetValueFormatter {
    enum PriceSource: String {
        case live
        case syncFallback
    }

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

    static func fallbackPrice(
        for token: PositionToken,
        fallbackUSDToDisplayRate: Decimal) -> Decimal? {
        fallbackPrice(for: token).map { $0 * fallbackUSDToDisplayRate }
    }

    /// Best available price in the display currency: live CoinGecko price, or the
    /// sync-time USD/amount ratio converted via `fallbackUSDToDisplayRate`.
    static func displayPrice(
        for token: PositionToken,
        livePrices: [String: Decimal],
        fallbackUSDToDisplayRate: Decimal = 1) -> Decimal {
        livePrice(for: token, livePrices: livePrices)
            ?? fallbackPrice(for: token, fallbackUSDToDisplayRate: fallbackUSDToDisplayRate)
            ?? .zero
    }

    /// Best available value in the display currency: live price * amount, or the
    /// sync-time usdValue converted via `fallbackUSDToDisplayRate`.
    static func displayValue(
        for token: PositionToken,
        livePrices: [String: Decimal],
        fallbackUSDToDisplayRate: Decimal = 1) -> Decimal {
        if let livePrice = livePrice(for: token, livePrices: livePrices) {
            return token.amount * livePrice
        }
        return token.usdValue * fallbackUSDToDisplayRate
    }

    /// Role-aware signed value: borrows negative, rewards zero, everything else positive.
    static func signedValue(
        for token: PositionToken,
        livePrices: [String: Decimal],
        fallbackUSDToDisplayRate: Decimal = 1) -> Decimal {
        let absoluteValue = displayValue(
            for: token,
            livePrices: livePrices,
            fallbackUSDToDisplayRate: fallbackUSDToDisplayRate)
        return switch token.role {
        case .borrow: -absoluteValue
        case .reward: Decimal.zero
        case .balance, .supply, .stake, .lpToken: absoluteValue
        }
    }
}
