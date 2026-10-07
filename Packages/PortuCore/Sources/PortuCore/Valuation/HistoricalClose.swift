import Foundation

/// The most recent daily close known for a price ID, with the UTC day it closed on.
public struct HistoricalClose: Equatable, Sendable {
    public let day: Date
    public let price: Decimal

    public init(day: Date, price: Decimal) {
        self.day = day
        self.price = price
    }
}
