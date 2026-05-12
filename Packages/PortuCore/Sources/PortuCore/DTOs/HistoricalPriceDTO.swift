import Foundation

public enum HistoricalPriceCalendar {
    public static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}

public struct HistoricalPriceDTO: Sendable, Equatable {
    public let coinGeckoId: String
    public let timestamp: Date
    public let day: Date
    public let usdPrice: Decimal

    public init(
        coinGeckoId: String,
        timestamp: Date,
        usdPrice: Decimal) {
        self.coinGeckoId = coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.timestamp = timestamp
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: timestamp)
        self.usdPrice = usdPrice
    }
}
