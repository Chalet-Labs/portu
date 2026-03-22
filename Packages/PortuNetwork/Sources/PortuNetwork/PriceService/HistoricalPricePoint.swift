import Foundation

public struct HistoricalPricePoint: Sendable, Equatable {
    public let date: Date
    public let price: Decimal

    public init(date: Date, price: Decimal) {
        self.date = date
        self.price = price
    }
}
