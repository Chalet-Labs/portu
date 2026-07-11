import Foundation

public struct CurrencyConversionRate: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(base.storageCode)-\(currency.storageCode)-\(Int(day.timeIntervalSince1970))"
    }

    public let base: FiatCurrency
    public let currency: FiatCurrency
    public let day: Date
    public let rate: Decimal

    public init(
        base: FiatCurrency = .usd,
        currency: FiatCurrency,
        day: Date,
        rate: Decimal) {
        self.base = base
        self.currency = currency
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.rate = rate
    }
}
