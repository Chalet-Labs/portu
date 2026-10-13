import Foundation

/// The most recent daily close known for a price ID, with the UTC day it closed on.
public struct HistoricalClose: Equatable, Sendable {
    /// UTC start of day; any intraday time passed in is dropped.
    public let day: Date
    public let price: Decimal

    public init(day: Date, price: Decimal) {
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.price = price
    }
}
