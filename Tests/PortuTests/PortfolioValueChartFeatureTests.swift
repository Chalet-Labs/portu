import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct PortfolioValueChartFeatureTests {
    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([AssetSnapshot.self, Asset.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private struct FirstDayFixture {
        let account: UUID
        let t1: Date
        let t2: Date
        let t3: Date
        let t4: Date
        let laterTimestamp: Date
    }

    /// Assets A (coinGeckoId), B (onchain identity), C (no Asset row at all);
    /// four snapshots on Jan 1 plus one on Jan 5 that must never project.
    private func seedFirstDayFixture(in context: ModelContext) throws -> FirstDayFixture {
        let batch = uuid(99)
        let account = uuid(10)

        context.insert(Asset(
            id: uuid(1),
            symbol: "BTC",
            name: "Bitcoin",
            coinGeckoId: "bitcoin",
            category: .major))
        context.insert(Asset(
            id: uuid(2),
            symbol: "WETH",
            name: "Wrapped Ether",
            upsertChain: .ethereum,
            upsertContract: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
            category: .major))

        let t1 = utcDate(2024, 1, 1, hour: 1)
        let t2 = utcDate(2024, 1, 1, hour: 2) // second row for same (account, asset A)
        let t3 = utcDate(2024, 1, 1, hour: 3)
        let t4 = utcDate(2024, 1, 1, hour: 4)
        let laterTimestamp = utcDate(2024, 1, 5, hour: 10)

        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t1, accountId: account, assetId: uuid(1),
            symbol: "BTC", category: .major, amount: 1, usdValue: 40000))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t2, accountId: account, assetId: uuid(1),
            symbol: "BTC", category: .major, amount: 1.1, usdValue: 44000))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t3, accountId: account, assetId: uuid(2),
            symbol: "WETH", category: .major, amount: 10, usdValue: 20000))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t4, accountId: account, assetId: uuid(3),
            symbol: "MISSING", category: .other, amount: 5, usdValue: 500))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: laterTimestamp, accountId: account, assetId: uuid(1),
            symbol: "BTC", category: .major, amount: 1, usdValue: 50000))
        try context.save()

        return FirstDayFixture(
            account: account,
            t1: t1, t2: t2, t3: t3, t4: t4,
            laterTimestamp: laterTimestamp)
    }

    /// BTC snapshots: two rows on Jan 1 (same account/asset, dedup must keep the
    /// earliest) and one on Jan 5 with a different amount.
    private func seedParityFixture(in context: ModelContext) throws -> (account: UUID, t1: Date, t2: Date, t5: Date) {
        let batch = uuid(99)
        let account = uuid(10)

        context.insert(Asset(id: uuid(1), symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major))

        let t1 = utcDate(2024, 1, 1, hour: 1)
        let t2 = utcDate(2024, 1, 1, hour: 2)
        let t5 = utcDate(2024, 1, 5, hour: 10)

        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t1, accountId: account, assetId: uuid(1),
            symbol: "BTC", category: .major, amount: 1, usdValue: 40000))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t2, accountId: account, assetId: uuid(1),
            symbol: "BTC", category: .major, amount: 1.1, usdValue: 44000))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: t5, accountId: account, assetId: uuid(1),
            symbol: "BTC", category: .major, amount: 2, usdValue: 90000))
        try context.save()

        return (account, t1, t2, t5)
    }

    // MARK: - estimateSource

    @Test func `estimateSource returns nil on empty store`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = PortfolioValueChartFeature.estimateSource(
            modelContext: context,
            overrides: [],
            chartStartDate: utcDate(2024, 1, 1))
        #expect(result == nil)
    }

    @Test func `estimateSource returns nil when earliest snapshot predates chart start`() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Snapshot on Jan 1 but chart starts Jan 5 — estimate would be empty, return nil.
        context.insert(AssetSnapshot(
            syncBatchId: uuid(99),
            timestamp: utcDate(2024, 1, 1),
            accountId: uuid(10),
            assetId: uuid(1),
            symbol: "BTC",
            category: .major,
            amount: 1,
            usdValue: 40000))
        try context.save()

        let result = PortfolioValueChartFeature.estimateSource(
            modelContext: context,
            overrides: [],
            chartStartDate: utcDate(2024, 1, 5))
        #expect(result == nil)
    }

    @Test func `estimateSource reports earliest timestamp and only first day entries`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let chartStart = utcDate(2024, 1, 1)
        let fixture = try seedFirstDayFixture(in: context)

        let source = try #require(
            PortfolioValueChartFeature.estimateSource(
                modelContext: context,
                overrides: [],
                chartStartDate: chartStart))

        #expect(source.firstRealSnapshotDate == fixture.t1)
        #expect(source.firstDayEntries.count == 4)

        let timestamps = Set(source.firstDayEntries.map(\.timestamp))
        #expect(timestamps == [fixture.t1, fixture.t2, fixture.t3, fixture.t4])
        #expect(timestamps.contains(fixture.laterTimestamp) == false)

        // Asset A coinGeckoId projected correctly.
        let btcEntry = source.firstDayEntries.first { $0.assetId == uuid(1) && $0.timestamp == fixture.t1 }
        #expect(btcEntry?.coinGeckoId == "bitcoin")

        // Asset B onchain identity projected correctly.
        let wethEntry = source.firstDayEntries.first { $0.assetId == uuid(2) }
        #expect(wethEntry?.onchainIdentity?.chain == .ethereum)

        // Missing asset row — coinGeckoId and onchainIdentity both nil.
        let missingEntry = source.firstDayEntries.first { $0.assetId == uuid(3) }
        #expect(missingEntry?.coinGeckoId == nil)
        #expect(missingEntry?.onchainIdentity == nil)
    }

    @Test func `estimateSource parity earliest holdings equal using all entries vs first day only`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let chartStart = utcDate(2024, 1, 1)
        let fixture = try seedParityFixture(in: context)

        let source = try #require(
            PortfolioValueChartFeature.estimateSource(
                modelContext: context,
                overrides: [],
                chartStartDate: chartStart))

        // Manually project all rows using the same field mapping as estimateSource:
        //   coinGeckoId from asset lookup, netUSDValue = usdValue - borrowUsdValue.
        let allEntries: [HistoricalEstimateSnapshotEntry] = [
            HistoricalEstimateSnapshotEntry(
                accountId: fixture.account, assetId: uuid(1), timestamp: fixture.t1,
                coinGeckoId: "bitcoin", coinGeckoIdOverride: nil,
                amount: 1, borrowAmount: 0, netUSDValue: 40000),
            HistoricalEstimateSnapshotEntry(
                accountId: fixture.account, assetId: uuid(1), timestamp: fixture.t2,
                coinGeckoId: "bitcoin", coinGeckoIdOverride: nil,
                amount: 1.1, borrowAmount: 0, netUSDValue: 44000),
            HistoricalEstimateSnapshotEntry(
                accountId: fixture.account, assetId: uuid(1), timestamp: fixture.t5,
                coinGeckoId: "bitcoin", coinGeckoIdOverride: nil,
                amount: 2, borrowAmount: 0, netUSDValue: 90000)
        ]

        let holdingsFromAll = PerformanceFeature.earliestEstimateHoldings(
            snapshots: allEntries,
            firstRealSnapshotDate: source.firstRealSnapshotDate,
            accountId: nil)

        let holdingsFromFirstDay = PerformanceFeature.earliestEstimateHoldings(
            snapshots: source.firstDayEntries,
            firstRealSnapshotDate: source.firstRealSnapshotDate,
            accountId: nil)

        // Drop-in replacement: later-day rows never affect the estimate.
        #expect(holdingsFromAll == holdingsFromFirstDay)
        // Sanity: the earliest Jan 1 entry (amount=1) wins the dedup, not later ones.
        #expect(holdingsFromFirstDay.count == 1)
        #expect(holdingsFromFirstDay.first?.amount == 1)
    }

    // MARK: - estimatedPoints (pure, no models)

    @Test func `estimatedPoints returns empty when backfill disabled`() {
        let account = uuid(10)
        let source = PortfolioValueChartEstimateSource(
            firstRealSnapshotDate: utcDate(2024, 1, 5, hour: 12),
            firstDayEntries: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: uuid(1),
                    timestamp: utcDate(2024, 1, 5, hour: 1),
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0)
            ])

        let result = PortfolioValueChartFeature.estimatedPoints(
            source: source,
            prices: [HistoricalPriceEntry(coinGeckoId: "bitcoin", day: utcDate(2024, 1, 1), usdPrice: 50000)],
            chartStartDate: utcDate(2024, 1, 1),
            isBackfillEnabled: false)

        #expect(result.isEmpty)
    }

    @Test func `estimatedPoints produces correct values exercising amount×price and fallbackUSDValue×ratio paths`() {
        // Two holdings:
        //   BTC (no fallbackUSDValue) → uses amount × price
        //   ETH (fallbackUSDValue = 20000, refPrice = 2000) → uses fallbackUSDValue × price / refPrice
        let account = uuid(10)
        // firstDayEntries must be on the same UTC day as firstRealSnapshotDate.
        let firstReal = utcDate(2024, 1, 5, hour: 12) // noon Jan 5
        let jan5Entry = utcDate(2024, 1, 5, hour: 1) // Jan 5 01:00 UTC (same UTC day)

        let source = PortfolioValueChartEstimateSource(
            firstRealSnapshotDate: firstReal,
            firstDayEntries: [
                // BTC: 1 BTC, no netUSDValue → HistoricalEstimateHolding.fallbackUSDValue = nil
                HistoricalEstimateSnapshotEntry(
                    accountId: account, assetId: uuid(11),
                    timestamp: jan5Entry,
                    coinGeckoId: "bitcoin", coinGeckoIdOverride: nil,
                    amount: 1, borrowAmount: 0, netUSDValue: nil),
                // ETH: 5 ETH, netUSDValue = 20000 → HistoricalEstimateHolding.fallbackUSDValue = 20000
                HistoricalEstimateSnapshotEntry(
                    accountId: account, assetId: uuid(12),
                    timestamp: jan5Entry,
                    coinGeckoId: "ethereum", coinGeckoIdOverride: nil,
                    amount: 5, borrowAmount: 0, netUSDValue: 20000)
            ])

        let jan1 = utcDate(2024, 1, 1)
        let jan3 = utcDate(2024, 1, 3)
        // Jan 5 midnight: passes the window filter ($0.day < firstReal noon) in estimatedPoints,
        // but the estimator's internal filter (day < firstRealDay = Jan 5 midnight) excludes it
        // from the chart while including it in the reference price pool.
        let jan5Midnight = utcDate(2024, 1, 5)

        let prices: [HistoricalPriceEntry] = [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: jan1, usdPrice: 50000),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: jan1, usdPrice: 1000),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: jan3, usdPrice: 55000),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: jan3, usdPrice: 1500),
            // Reference-only price on firstRealDay midnight: excluded from chart, sets refPrice.
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: jan5Midnight, usdPrice: 2000)
        ]

        let result = PortfolioValueChartFeature.estimatedPoints(
            source: source,
            prices: prices,
            chartStartDate: utcDate(2024, 1, 1),
            isBackfillEnabled: true)

        // Jan 1: BTC = 1 × 50000 = 50000; ETH = 20000 × 1000 / 2000 = 10000 → total 60000
        // Jan 3: BTC = 1 × 55000 = 55000; ETH = 20000 × 1500 / 2000 = 15000 → total 70000
        // Jan 5 midnight: excluded from chart (== firstRealDay, not strictly before it)
        #expect(result.count == 2)
        let jan1Point = result.first { $0.date == jan1 }
        let jan3Point = result.first { $0.date == jan3 }
        #expect(jan1Point?.value == 60000)
        #expect(jan3Point?.value == 70000)
        #expect(result.allSatisfy { $0.kind == .estimated })
    }
}
