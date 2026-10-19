import Foundation
@testable import Portu
import PortuCore
import Testing

struct PerformanceHistoricalPricesTests {
    @Test func `merged historical price entries pick the row with the latest fetchedAt on duplicate days`() {
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let olderFetch = day
        let newerFetch = day.addingTimeInterval(3600)

        let freshRow = HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            currency: .usd,
            price: 41000,
            fetchedAt: newerFetch)
        let staleRow = HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            currency: .usd,
            price: 40000,
            fetchedAt: olderFetch)

        let entries = PerformanceDataShaping.mergedHistoricalPriceEntries(
            from: [freshRow, staleRow],
            displayCurrency: .usd,
            context: .usd)

        #expect(entries.map(\.usdPrice) == [41000])
    }

    @Test func `merged historical price entries normalize day to utc start of day`() {
        let midday = Date(timeIntervalSince1970: 1_704_067_200 + 12 * 3600)
        let normalizedDay = HistoricalPriceCalendar.utcStartOfDay(for: midday)

        let usdRow = HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: midday,
            currency: .usd,
            price: 41000,
            fetchedAt: midday)
        let displayCurrencyRow = HistoricalPricePoint(
            coinGeckoId: "ethereum",
            day: midday,
            currency: .eur,
            price: 2000,
            fetchedAt: midday)

        let entries = PerformanceDataShaping.mergedHistoricalPriceEntries(
            from: [usdRow, displayCurrencyRow],
            displayCurrency: .eur,
            context: .usd)

        #expect(entries.allSatisfy { $0.day == normalizedDay })
    }
}
