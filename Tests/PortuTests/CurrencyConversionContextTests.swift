import Foundation
@testable import Portu
import PortuCore
import Testing

struct CurrencyConversionContextTests {
    @Test func `dictionary initializer deterministically keeps the chronologically latest rate for a colliding day`() throws {
        let day = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let morning = day.addingTimeInterval(9 * 3600)
        let evening = day.addingTimeInterval(18 * 3600)

        // Listed with the later timestamp first — dictionary literal order must not
        // influence which rate wins for the colliding day.
        let context = try CurrencyConversionContext(
            displayCurrency: .eur,
            currentUSDToDisplayRate: 1,
            historicalUSDToDisplayRatesByDay: [
                evening: #require(Decimal(string: "0.95")),
                morning: #require(Decimal(string: "0.90"))
            ])

        #expect(context.rate(for: day) == 0.95)
    }

    @Test func `rate for today prefers the live spot rate over a stale cached historical row`() throws {
        let today = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let yesterday = today.addingTimeInterval(-86400)

        // The historical-FX top-up only fetches today's row once per day, so it can
        // hold a rate that is already stale relative to the continuously-refreshed
        // currentUSDToDisplayRate.
        let context = try CurrencyConversionContext(
            displayCurrency: .eur,
            currentUSDToDisplayRate: #require(Decimal(string: "1.10")),
            historicalUSDToDisplayRatesByDay: [
                today: #require(Decimal(string: "1.05")),
                yesterday: #require(Decimal(string: "1.00"))
            ])

        #expect(context.rate(for: today, today: today) == 1.10)
        // Past days are unaffected — the cached historical rate still wins there.
        #expect(context.rate(for: yesterday, today: today) == 1.00)
    }
}
