import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// The estimate ends at the first recorded point the chart draws in its scope and never runs over
/// the recorded series (U7). The holdings still come from the first non-ignored asset batch.
///
/// The fixture: the first non-ignored asset batch is Jan 5 (12:00 UTC), BTC 1 at 50,000 for the
/// main account and BTC 2 at 100,000 for another, with totals recorded in the same sync. Closes
/// climb 40,000 / 45,000 / 48,000 / 49,000 / 50,000 over Jan 1–5, so with the reference close on
/// Jan 5 an estimated day is 3 × close globally and 1 × close for the main account. The earliest
/// batch varies per test; when it puts a recorded point on Jan 3, only Jan 1 and Jan 2 may stay.
@MainActor
struct EstimateWindowEndTests {
    private static let main = id(10)
    private static let other = id(11)
    private static let btc = id(1)
    private static let scam = id(2)

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()
    }

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private static let chartStart = utcDate(2024, 1, 1)
    private static let firstRecorded = utcDate(2024, 1, 3, hour: 12)
    private static let firstAssetBatch = utcDate(2024, 1, 5, hour: 12)
    private static let beforeStart = utcDate(2023, 12, 30, hour: 12)
    private static let closes: [(day: Int, price: Decimal)] = [(1, 40000), (2, 45000), (3, 48000), (4, 49000), (5, 50000)]

    private static let fullDays = (1 ... 4).map { utcDate(2024, 1, $0) }
    private static let fullGlobal: [Decimal] = [120_000, 135_000, 144_000, 147_000]
    private static let fullAccount: [Decimal] = [40000, 45000, 48000, 49000]
    private static let clippedDays = Array(fullDays.prefix(2))
    private static let clippedGlobal = Array(fullGlobal.prefix(2))
    private static let clippedAccount = Array(fullAccount.prefix(2))

    /// What the earliest sync recorded, before the Jan 5 batch.
    private enum EarliestBatch {
        /// Nothing earlier: totals and asset rows share the Jan 5 sync.
        case sameSync
        /// Jan 3: totals plus asset rows that are all ignored now (rows from before N1).
        case ignoredOnly
        /// Jan 3: totals with no asset rows (an all-zero first sync, or only failed accounts).
        case totalsOnly
        /// Dec 30, before the range start: totals with no asset rows.
        case totalsBeforeStart
        /// Jan 3: a partial total and a stale account row, which the account chart never draws.
        case staleAccountOnly
    }

    private func makeContainer(_ earliest: EarliestBatch) throws -> ModelContainer {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        context.insert(Asset(id: Self.btc, symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major))
        context.insert(Asset(id: Self.scam, symbol: "SCAM", name: "Scam", coinGeckoId: "scam-token", category: .other))
        for (batch, timestamp) in [(Self.id(91), Self.firstAssetBatch), (Self.id(92), Self.utcDate(2024, 1, 6, hour: 12))] {
            insertAssetRows(context, batch: batch, at: timestamp)
            insertTotals(context, at: timestamp, total: 150_000, main: 50000, isFresh: true)
        }

        switch earliest {
        case .sameSync:
            break
        case .ignoredOnly:
            context.insert(AssetSnapshot(
                syncBatchId: Self.id(90), timestamp: Self.firstRecorded, accountId: Self.main, assetId: Self.scam,
                symbol: "SCAM", category: .other, amount: 1000, usdValue: 5000))
            insertTotals(context, at: Self.firstRecorded, total: 5000, main: 5000, isFresh: true)
            context.insert(TokenPricingOverride(assetId: Self.scam, isIgnored: true))
        case .totalsOnly:
            insertTotals(context, at: Self.firstRecorded, total: 0, main: 0, isFresh: true, isPartial: true)
        case .totalsBeforeStart:
            insertTotals(context, at: Self.beforeStart, total: 0, main: 0, isFresh: true)
        case .staleAccountOnly:
            insertTotals(context, at: Self.firstRecorded, total: 100, main: 100, isFresh: false, isPartial: true)
        }

        for close in Self.closes {
            context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Self.utcDate(2024, 1, close.day), usdPrice: close.price))
            context.insert(HistoricalPricePoint(coinGeckoId: "scam-token", day: Self.utcDate(2024, 1, close.day), usdPrice: 5))
        }
        try context.save()
        return container
    }

    private func insertAssetRows(_ context: ModelContext, batch: UUID, at timestamp: Date) {
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: timestamp, accountId: Self.main, assetId: Self.btc,
            symbol: "BTC", category: .major, amount: 1, usdValue: 50000))
        context.insert(AssetSnapshot(
            syncBatchId: batch, timestamp: timestamp, accountId: Self.other, assetId: Self.btc,
            symbol: "BTC", category: .major, amount: 2, usdValue: 100_000))
    }

    private func insertTotals(
        _ context: ModelContext,
        at timestamp: Date,
        total: Decimal,
        main: Decimal,
        isFresh: Bool,
        isPartial: Bool = false) {
        let batch = UUID()
        context.insert(PortfolioSnapshot(
            syncBatchId: batch, timestamp: timestamp, totalValue: total,
            idleValue: total, deployedValue: 0, debtValue: 0, isPartial: isPartial))
        context.insert(AccountSnapshot(
            syncBatchId: batch, timestamp: timestamp, accountId: Self.main, totalValue: main, isFresh: isFresh))
    }

    private func overrides(_ container: ModelContainer) throws -> [TokenPricingOverrideSnapshot] {
        try container.mainContext.fetch(FetchDescriptor<TokenPricingOverride>()).map(TokenPricingOverrideSnapshot.init)
    }

    private func overviewSource(_ container: ModelContainer) async throws -> PortfolioValueChartEstimateSource? {
        let overrides = try overrides(container)
        return await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)
            .estimateSource(overrides: overrides, chartStartDate: Self.chartStart)
    }

    private func overviewEstimate(_ container: ModelContainer) async throws -> [HistoricalPortfolioValuePoint] {
        guard let source = try await overviewSource(container) else { return [] }
        let prices = Self.closes.map {
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: Self.utcDate(2024, 1, $0.day), usdPrice: $0.price)
        }
        return PortfolioValueChartFeature.estimatedPoints(
            source: source,
            prices: prices,
            chartStartDate: Self.chartStart,
            isBackfillEnabled: true)
    }

    private func performanceChart(
        _ container: ModelContainer,
        accountId: UUID? = nil) async throws -> PerformanceValueChartData {
        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        return try await fetcher.load(PerformanceDataRequest(
            accountId: accountId,
            startDate: Self.chartStart,
            chartMode: .value,
            historicalBackfillEnabled: true)).valueChart
    }

    // MARK: - The earliest recorded point comes before the first non-ignored asset row

    @Test func `the Overview estimate ends at a total recorded with only ignored asset rows`() async throws {
        let container = try makeContainer(.ignoredOnly)

        let points = try await overviewEstimate(container)

        #expect(points.map(\.date) == Self.clippedDays)
        #expect(points.map(\.value) == Self.clippedGlobal)
    }

    @Test func `the Overview estimate ends at a total recorded with no asset rows`() async throws {
        let container = try makeContainer(.totalsOnly)

        let points = try await overviewEstimate(container)

        #expect(points.map(\.date) == Self.clippedDays)
        #expect(points.map(\.value) == Self.clippedGlobal)
    }

    @Test func `the Performance estimate ends at a total recorded with only ignored asset rows`() async throws {
        let container = try makeContainer(.ignoredOnly)

        let global = try await performanceChart(container)
        let account = try await performanceChart(container, accountId: Self.main)
        try #require(global.points.first?.date == Self.firstRecorded, "The global chart draws the Jan 3 total")
        try #require(account.points.first?.date == Self.firstRecorded, "The account chart draws the Jan 3 row")

        #expect(global.estimatedPoints.map(\.date) == Self.clippedDays)
        #expect(global.estimatedPoints.map(\.value) == Self.clippedGlobal)
        #expect(account.estimatedPoints.map(\.date) == Self.clippedDays)
        #expect(account.estimatedPoints.map(\.value) == Self.clippedAccount)
    }

    @Test func `the Performance estimate ends at a total recorded with no asset rows`() async throws {
        let container = try makeContainer(.totalsOnly)

        let global = try await performanceChart(container)
        let account = try await performanceChart(container, accountId: Self.main)
        try #require(global.points.first?.date == Self.firstRecorded, "The global chart draws the Jan 3 total")
        try #require(account.points.first?.date == Self.firstRecorded, "The account chart draws the Jan 3 row")

        #expect(global.estimatedPoints.map(\.date) == Self.clippedDays)
        #expect(global.estimatedPoints.map(\.value) == Self.clippedGlobal)
        #expect(account.estimatedPoints.map(\.date) == Self.clippedDays)
        #expect(account.estimatedPoints.map(\.value) == Self.clippedAccount)
    }

    /// The window ends before the range starts, so the estimate is empty, as it already is when the
    /// first asset row predates the range.
    @Test func `a total recorded before the range start leaves no estimate`() async throws {
        let container = try makeContainer(.totalsBeforeStart)

        let overview = try await overviewEstimate(container)
        let global = try await performanceChart(container)
        let account = try await performanceChart(container, accountId: Self.main)

        #expect(overview.isEmpty)
        #expect(global.estimatedPoints.isEmpty)
        #expect(account.estimatedPoints.isEmpty)
    }

    // MARK: - Guards

    @Test func `totals and asset rows from the same sync leave the estimate as it is`() async throws {
        let container = try makeContainer(.sameSync)

        let overview = try await overviewEstimate(container)
        let global = try await performanceChart(container)
        let account = try await performanceChart(container, accountId: Self.main)

        #expect(overview.map(\.date) == Self.fullDays)
        #expect(overview.map(\.value) == Self.fullGlobal)
        #expect(global.estimatedPoints.map(\.date) == Self.fullDays)
        #expect(global.estimatedPoints.map(\.value) == Self.fullGlobal)
        #expect(account.estimatedPoints.map(\.date) == Self.fullDays)
        #expect(account.estimatedPoints.map(\.value) == Self.fullAccount)
    }

    /// The holdings and their date stay on the first non-ignored batch even when the window ends
    /// earlier, so the Jan 5 values (50,000 + 100,000) still anchor the estimate.
    @Test func `the holdings still come from the first non-ignored asset batch`() async throws {
        let container = try makeContainer(.ignoredOnly)

        let source = try #require(try await overviewSource(container))

        #expect(source.firstRealSnapshotDate == Self.firstAssetBatch)
        #expect(source.firstDayEntries.map(\.assetId) == [Self.btc, Self.btc])
        #expect(source.firstDayEntries.compactMap(\.netUSDValue).reduce(0, +) == 150_000)
    }

    /// The account chart draws local rows only from the first fresh one on, so a stale row before
    /// it is not a recorded point there and does not end the account estimate.
    @Test func `a stale account row before the first fresh one leaves the account estimate as it is`() async throws {
        let container = try makeContainer(.staleAccountOnly)

        let account = try await performanceChart(container, accountId: Self.main)

        #expect(account.points.first?.date == Self.firstAssetBatch)
        #expect(account.estimatedPoints.map(\.date) == Self.fullDays)
        #expect(account.estimatedPoints.map(\.value) == Self.fullAccount)
    }
}
