import Foundation

/// Published by PriceService. AppState subscribes and updates both maps atomically.
public struct PriceUpdate: Sendable, Equatable {
    /// coinGeckoId → USD price
    public let prices: [String: Decimal]
    /// coinGeckoId → 24h percentage change
    public let changes24h: [String: Decimal]

    public init(prices: [String: Decimal], changes24h: [String: Decimal]) {
        self.prices = prices
        self.changes24h = changes24h
    }
}
