import Foundation

/// Published by PriceService. AppState subscribes and updates both maps atomically.
public struct PriceUpdate: Sendable, Equatable {
    public let currency: FiatCurrency
    /// coinGeckoId → price in `currency`
    public let prices: [String: Decimal]
    /// coinGeckoId → 24h percentage change
    public let changes24h: [String: Decimal]

    public init(
        currency: FiatCurrency = .default,
        prices: [String: Decimal],
        changes24h: [String: Decimal]) {
        self.currency = currency
        self.prices = prices
        self.changes24h = changes24h
    }
}
