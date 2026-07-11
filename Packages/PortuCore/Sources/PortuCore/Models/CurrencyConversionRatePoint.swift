import Foundation
import SwiftData

@Model
public final class CurrencyConversionRatePoint {
    #Index<CurrencyConversionRatePoint>([\.day], [\.cacheKey])

    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var cacheKey: String
    public var baseCurrency: FiatCurrency
    public var quoteCurrency: FiatCurrency
    public var day: Date
    public var rate: Decimal
    public var fetchedAt: Date

    public init(
        id: UUID = UUID(),
        baseCurrency: FiatCurrency,
        quoteCurrency: FiatCurrency,
        day: Date,
        rate: Decimal,
        fetchedAt: Date = .now) {
        let normalizedDay = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.id = id
        self.cacheKey = Self.cacheKey(baseCurrency: baseCurrency, quoteCurrency: quoteCurrency, day: normalizedDay)
        self.baseCurrency = baseCurrency
        self.quoteCurrency = quoteCurrency
        self.day = normalizedDay
        self.rate = rate
        self.fetchedAt = fetchedAt
    }

    public convenience init(_ rate: CurrencyConversionRate, fetchedAt: Date = .now) {
        self.init(
            baseCurrency: rate.base,
            quoteCurrency: rate.currency,
            day: rate.day,
            rate: rate.rate,
            fetchedAt: fetchedAt)
    }

    public func update(rate: Decimal, fetchedAt: Date) {
        self.rate = rate
        self.fetchedAt = fetchedAt
    }

    public static func cacheKey(baseCurrency: FiatCurrency, quoteCurrency: FiatCurrency, day: Date) -> String {
        let normalizedDay = HistoricalPriceCalendar.utcStartOfDay(for: day)
        return "\(baseCurrency.storageCode):\(quoteCurrency.storageCode):\(Int(normalizedDay.timeIntervalSince1970))"
    }
}
