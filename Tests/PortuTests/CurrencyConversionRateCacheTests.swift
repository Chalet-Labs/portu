import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct CurrencyConversionRateCacheTests {
    @Test func `cache writer normalizes utc day and upserts per currency`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let laterSameDay = day.addingTimeInterval(3600)

        let first = try CurrencyConversionRateCacheWriter.upsert(
            [
                CurrencyConversionRate(currency: .eur, day: day, rate: #require(Decimal(string: "0.9"))),
                CurrencyConversionRate(currency: .chf, day: day, rate: #require(Decimal(string: "0.88")))
            ],
            in: context,
            fetchedAt: Date(timeIntervalSince1970: 10))
        let second = try CurrencyConversionRateCacheWriter.upsert(
            [
                CurrencyConversionRate(currency: .eur, day: laterSameDay, rate: #require(Decimal(string: "0.91")))
            ],
            in: context,
            fetchedAt: Date(timeIntervalSince1970: 20))

        let rows = try context.fetch(FetchDescriptor<CurrencyConversionRatePoint>())
            .sorted { $0.quoteCurrency.storageCode < $1.quoteCurrency.storageCode }

        #expect(first.inserted == 2)
        #expect(first.updated == 0)
        #expect(second.inserted == 0)
        #expect(second.updated == 1)
        #expect(rows.map(\.quoteCurrency) == [.chf, .eur])
        #expect(rows.map(\.day) == [
            HistoricalPriceCalendar.utcStartOfDay(for: day),
            HistoricalPriceCalendar.utcStartOfDay(for: day)
        ])
        #expect(try rows.map(\.rate) == [#require(Decimal(string: "0.88")), #require(Decimal(string: "0.91"))])
    }

    @Test func `refreshing usd returns one without persisting rows`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        nonisolated(unsafe) var currentRequests: [FiatCurrency] = []
        nonisolated(unsafe) var historicalRequests: [(FiatCurrency, Int)] = []
        let client = CurrencyConversionClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { _, _ in [] },
                fetchCurrentUSDConversionRate: { currency in
                    currentRequests.append(currency)
                    return 2
                },
                fetchHistoricalUSDConversionRates: { currency, days in
                    historicalRequests.append((currency, days))
                    return []
                },
                invalidateCache: {}),
            now: { Date(timeIntervalSince1970: 30) })

        let result = try await client.refreshRates(.usd, HistoricalPriceBackfillSettings.chartHorizonDays)

        #expect(result.currentUSDToDisplayRate == 1)
        #expect(result.insertedHistoricalRates == 0)
        #expect(result.updatedHistoricalRates == 0)
        #expect(currentRequests.isEmpty)
        #expect(historicalRequests.isEmpty)
        #expect(try context.fetch(FetchDescriptor<CurrencyConversionRatePoint>()).isEmpty)
    }
}
