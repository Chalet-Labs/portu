import Foundation
@testable import Portu
import Testing

struct PerformanceHistoricalPriceChangeTests {
    @Test func `computes period price changes from first and last cached prices`() {
        let day1 = date(2024, 1, 1)
        let day2 = date(2024, 1, 2)

        let changes = PerformanceFeature.computeHistoricalPriceChanges(
            rows: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day1, usdPrice: 40000),
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day2, usdPrice: 44000),
                HistoricalPriceEntry(coinGeckoId: "ethereum", day: day1, usdPrice: 2000),
                HistoricalPriceEntry(coinGeckoId: "ethereum", day: day2, usdPrice: 1800)
            ])

        #expect(changes.map(\.coinGeckoId) == ["bitcoin", "ethereum"])
        #expect(changes[0].percentChange == Decimal(string: "0.1")!)
        #expect(changes[1].percentChange == Decimal(string: "-0.1")!)
    }

    @Test func `filters historical price rows to held ids for selected account`() {
        let account = UUID()
        let other = UUID()
        let btc = UUID()
        let eth = UUID()
        let sol = UUID()
        let empty = UUID()
        let startDate = date(2024, 1, 1)
        let day2 = date(2024, 1, 2)

        let rows = [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: startDate, usdPrice: 40000),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: startDate, usdPrice: 2000),
            HistoricalPriceEntry(coinGeckoId: "solana", day: startDate, usdPrice: 100),
            HistoricalPriceEntry(coinGeckoId: "empty", day: startDate, usdPrice: 1),
            HistoricalPriceEntry(coinGeckoId: "cache-only", day: day2, usdPrice: 1)
        ]

        let filtered = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: rows,
            holdings: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: btc,
                    timestamp: startDate,
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: other,
                    assetId: eth,
                    timestamp: startDate,
                    coinGeckoId: "ethereum",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: sol,
                    timestamp: startDate,
                    coinGeckoId: "old-sol",
                    coinGeckoIdOverride: "solana",
                    amount: 1,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: empty,
                    timestamp: startDate,
                    coinGeckoId: "empty",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 1)
            ],
            startDate: startDate,
            accountId: account)

        #expect(filtered.map(\.coinGeckoId) == ["bitcoin", "solana"])
    }

    @Test func `earliest estimate holdings skip zero net rows and prefer overrides`() {
        let account = UUID()
        let zeroNet = UUID()
        let overridden = UUID()
        let firstReal = date(2024, 1, 2)

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: zeroNet,
                    timestamp: firstReal,
                    coinGeckoId: "missing-price",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 1),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: overridden,
                    timestamp: firstReal,
                    coinGeckoId: "old-id",
                    coinGeckoIdOverride: "new-id",
                    amount: 2,
                    borrowAmount: 0)
            ],
            firstRealSnapshotDate: firstReal,
            accountId: account)

        #expect(holdings == [
            HistoricalEstimateHolding(
                accountId: account,
                assetId: overridden,
                coinGeckoId: "new-id",
                amount: 2)
        ])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
