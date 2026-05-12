import Foundation
@testable import Portu
import PortuCore
import Testing

struct HistoricalPortfolioEstimatorTests {
    @Test func `estimates values before first real snapshot using earliest holdings`() {
        let account = uuid(1)
        let btc = uuid(10)
        let eth = uuid(11)
        let day1 = date(2024, 1, 1)
        let firstReal = date(2024, 1, 3)

        let holdings = [
            HistoricalEstimateHolding(accountId: account, assetId: btc, coinGeckoId: "bitcoin", amount: 2),
            HistoricalEstimateHolding(accountId: account, assetId: eth, coinGeckoId: "ethereum", amount: 10)
        ]
        let prices = [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day1, usdPrice: 40000),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: day1, usdPrice: 2000),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: firstReal, usdPrice: 45000)
        ]

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: prices,
            startDate: day1,
            firstRealSnapshotDate: firstReal,
            accountId: nil)

        #expect(points == [
            HistoricalPortfolioValuePoint(date: day1, value: 100_000, kind: .estimated)
        ])
    }

    @Test func `account filter estimates only matching account holdings`() {
        let account = uuid(1)
        let other = uuid(2)
        let btc = uuid(10)
        let day = date(2024, 1, 1)
        let firstReal = date(2024, 1, 2)

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: [
                HistoricalEstimateHolding(accountId: account, assetId: btc, coinGeckoId: "bitcoin", amount: 2),
                HistoricalEstimateHolding(accountId: other, assetId: btc, coinGeckoId: "bitcoin", amount: 5)
            ],
            prices: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day, usdPrice: 40000)
            ],
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: account)

        #expect(points.map(\.value) == [80000])
    }

    @Test func `estimator skips days with incomplete prices`() {
        let account = uuid(1)
        let day = date(2024, 1, 1)
        let firstReal = date(2024, 1, 2)

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: [
                HistoricalEstimateHolding(accountId: account, assetId: uuid(10), coinGeckoId: "bitcoin", amount: 1),
                HistoricalEstimateHolding(accountId: account, assetId: uuid(11), coinGeckoId: "ethereum", amount: 1)
            ],
            prices: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day, usdPrice: 40000)
            ],
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: nil)

        #expect(points.isEmpty)
    }

    @Test func `estimator normalizes coin gecko ids and skips empty ids`() {
        let account = uuid(1)
        let day = date(2024, 1, 1)
        let firstReal = date(2024, 1, 2)

        let points = HistoricalPortfolioEstimator.estimatedValues(
            holdings: [
                HistoricalEstimateHolding(accountId: account, assetId: uuid(10), coinGeckoId: " Bitcoin ", amount: 2),
                HistoricalEstimateHolding(accountId: account, assetId: uuid(11), coinGeckoId: " ", amount: 100)
            ],
            prices: [
                HistoricalPriceEntry(coinGeckoId: "BITCOIN", day: day, usdPrice: 40000),
                HistoricalPriceEntry(coinGeckoId: "", day: day, usdPrice: 999_999)
            ],
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: nil)

        #expect(points.map(\.value) == [80000])
    }

    @Test func `duplicate price rows produce same estimate regardless of input order`() {
        let account = uuid(1)
        let day = date(2024, 1, 1)
        let firstReal = date(2024, 1, 2)
        let holdings = [
            HistoricalEstimateHolding(accountId: account, assetId: uuid(10), coinGeckoId: "bitcoin", amount: 2)
        ]
        let prices = [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day, usdPrice: 40000),
            HistoricalPriceEntry(coinGeckoId: "BITCOIN", day: day, usdPrice: 41000)
        ]

        let first = HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: prices,
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: nil)
        let reversed = HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: prices.reversed(),
            startDate: day,
            firstRealSnapshotDate: firstReal,
            accountId: nil)

        #expect(first == reversed)
        #expect(first.map(\.value) == [82000])
    }

    @Test func `real values keep latest input per utc day`() {
        let day1Morning = date(2024, 1, 1, hour: 9)
        let day1Evening = date(2024, 1, 1, hour: 22)
        let day2Morning = date(2024, 1, 2, hour: 9)

        let points = HistoricalPortfolioEstimator.realValues([
            (day2Morning, 300),
            (day1Evening, 200),
            (day1Morning, 100)
        ])

        #expect(points == [
            HistoricalPortfolioValuePoint(date: date(2024, 1, 1), value: 200, kind: .real),
            HistoricalPortfolioValuePoint(date: date(2024, 1, 2), value: 300, kind: .real)
        ])
        #expect(Set(points.map(\.id)).count == points.count)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        date(year, month, day, hour: 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}
