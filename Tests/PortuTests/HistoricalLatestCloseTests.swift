import Foundation
@testable import Portu
import PortuCore
import Testing

struct HistoricalLatestCloseTests {
    private let oldDay = Date(timeIntervalSince1970: 0)
    private let latestDay = Date(timeIntervalSince1970: 172_800)

    @Test func `latest closes keep the newest day per canonical id`() {
        let closes = OverviewHistoricalPriceChangeFeature.latestCloses(from: [
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: oldDay, usdPrice: 1),
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: latestDay, usdPrice: 3),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: oldDay, usdPrice: 100)
        ])

        #expect(closes["asset:base:0xabc"] == HistoricalClose(day: latestDay, price: 3))
        #expect(closes["zapper:base:0xabc"] == nil)
        #expect(closes["bitcoin"] == HistoricalClose(day: oldDay, price: 100))
    }

    @Test func `latest closes normalize the day to the UTC start of day`() {
        let midday = latestDay.addingTimeInterval(12 * 3600)

        let closes = OverviewHistoricalPriceChangeFeature.latestCloses(from: [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: midday, usdPrice: 100)
        ])

        #expect(closes["bitcoin"]?.day == latestDay)
    }

    @Test func `latest closes break same day ties by the higher price and skip non positive prices`() {
        let closes = OverviewHistoricalPriceChangeFeature.latestCloses(from: [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: latestDay, usdPrice: 100),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: latestDay, usdPrice: 105),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: latestDay, usdPrice: 101),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: latestDay, usdPrice: 0)
        ])

        #expect(closes["bitcoin"] == HistoricalClose(day: latestDay, price: 105))
        #expect(closes["ethereum"] == nil)
    }

    @Test func `latest prices are the latest closes without their day`() {
        let entries = [
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: oldDay, usdPrice: 1),
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: latestDay, usdPrice: 3),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: latestDay, usdPrice: 100)
        ]

        let prices = OverviewHistoricalPriceChangeFeature.latestPrices(from: entries)
        let closes = OverviewHistoricalPriceChangeFeature.latestCloses(from: entries)

        #expect(prices == closes.mapValues(\.price))
    }
}
