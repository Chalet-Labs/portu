import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// The multi-asset `AssetSnapshot` readers leave out the assets that are ignored now, including
/// rows recorded before the ignore (spec N2, T3): the Performance category chart and estimate,
/// and the Overview value-chart estimate. The bottom panel already reads through the current
/// valuation, which drops ignored assets, so it is a guard here.
///
/// The fixture: rows on Jan 5 and Jan 6 (12:00 UTC) for the main account (BTC 1 at 50,000 and
/// SCAM 1,000 at 5,000) and another account (BTC 2 at 100,000), with flat closes on Jan 2–4
/// (bitcoin 50,000, scam-token 5). Every estimated day is therefore the first-day values:
/// 155,000 globally and 55,000 for the main account, or 150,000 and 50,000 without SCAM.
@MainActor
struct IgnoredAssetSnapshotReaderTests {
    private static let main = id(10)
    private static let other = id(11)
    private static let btc = id(1)
    private static let scam = id(2)

    private static let btcCategory = PortfolioCategoryResolver.defaults
        .resolve(symbol: "BTC", legacyCategory: .major).id.uuidString
    private static let scamCategory = PortfolioCategoryResolver.defaults
        .resolve(symbol: "SCAM", legacyCategory: .other).id.uuidString

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()
    }

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private static let chartStart = utcDate(2024, 1, 1)
    private static let firstReal = utcDate(2024, 1, 5, hour: 12)
    private static let earlyIgnored = utcDate(2023, 12, 30, hour: 12)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory().makeInMemory()
    }

    /// Seeds the fixture. `earlyIgnoredRow` adds a SCAM row on Dec 30, before the chart start.
    private func seed(_ context: ModelContext, earlyIgnoredRow: Bool = false) throws {
        context.insert(Asset(id: Self.btc, symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major))
        context.insert(Asset(id: Self.scam, symbol: "SCAM", name: "Scam", coinGeckoId: "scam-token", category: .other))
        for (batch, timestamp) in [(Self.id(91), Self.firstReal), (Self.id(92), Self.utcDate(2024, 1, 6, hour: 12))] {
            context.insert(AssetSnapshot(
                syncBatchId: batch, timestamp: timestamp, accountId: Self.main, assetId: Self.btc,
                symbol: "BTC", category: .major, amount: 1, usdValue: 50000))
            context.insert(AssetSnapshot(
                syncBatchId: batch, timestamp: timestamp, accountId: Self.main, assetId: Self.scam,
                symbol: "SCAM", category: .other, amount: 1000, usdValue: 5000))
            context.insert(AssetSnapshot(
                syncBatchId: batch, timestamp: timestamp, accountId: Self.other, assetId: Self.btc,
                symbol: "BTC", category: .major, amount: 2, usdValue: 100_000))
        }
        if earlyIgnoredRow {
            context.insert(AssetSnapshot(
                syncBatchId: Self.id(90), timestamp: Self.earlyIgnored, accountId: Self.main, assetId: Self.scam,
                symbol: "SCAM", category: .other, amount: 1000, usdValue: 5000))
        }
        for day in 2 ... 4 {
            context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Self.utcDate(2024, 1, day), usdPrice: 50000))
            context.insert(HistoricalPricePoint(coinGeckoId: "scam-token", day: Self.utcDate(2024, 1, day), usdPrice: 5))
        }
        try context.save()
    }

    /// Ignore overrides for `assetIDs` plus `extra` unrelated ignored IDs, stored and returned.
    @discardableResult
    private func ignore(
        _ assetIDs: [UUID],
        extra: Int = 0,
        in context: ModelContext) throws -> [TokenPricingOverrideSnapshot] {
        let overrides = (assetIDs + (0 ..< extra).map { _ in UUID() })
            .map { TokenPricingOverride(assetId: $0, isIgnored: true) }
        for override in overrides {
            context.insert(override)
        }
        try context.save()
        return overrides.map(TokenPricingOverrideSnapshot.init)
    }

    private func load(
        _ container: ModelContainer,
        accountId: UUID? = nil,
        mode: PerformanceChartMode) async throws -> PerformanceDataSnapshot {
        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        return try await fetcher.load(PerformanceDataRequest(
            accountId: accountId,
            startDate: Self.chartStart,
            chartMode: mode,
            historicalBackfillEnabled: true))
    }

    private func estimate(_ container: ModelContainer, accountId: UUID? = nil) async throws -> [Decimal] {
        try await load(container, accountId: accountId, mode: .value).valueChart.estimatedPoints.map(\.value)
    }

    private func categoryIDs(_ container: ModelContainer, accountId: UUID? = nil) async throws -> Set<String> {
        try await Set(load(container, accountId: accountId, mode: .assets).categoryChart.points.map(\.categoryID))
    }

    private func overviewSource(
        _ container: ModelContainer,
        overrides: [TokenPricingOverrideSnapshot]) async -> PortfolioValueChartEstimateSource? {
        await PortfolioValueChartEstimateFetcher(modelContainer: container)
            .estimateSource(overrides: overrides, chartStartDate: Self.chartStart)
    }

    private func assetIDs(_ source: PortfolioValueChartEstimateSource?) -> Set<UUID> {
        Set(source?.firstDayEntries.map(\.assetId) ?? [])
    }

    // MARK: - Fixture sanity and the empty ignored set

    @Test func `with nothing ignored every reader keeps every asset`() async throws {
        try #require(Self.btcCategory != Self.scamCategory, "Each asset needs its own category")
        let container = try makeContainer()
        try seed(container.mainContext)
        container.mainContext.insert(TokenPricingOverride(assetId: Self.btc, alwaysShow: true))
        try container.mainContext.save()

        #expect(try await estimate(container) == [155_000, 155_000, 155_000])
        #expect(try await estimate(container, accountId: Self.main) == [55000, 55000, 55000])
        #expect(try await categoryIDs(container) == [Self.btcCategory, Self.scamCategory])
        #expect(try await categoryIDs(container, accountId: Self.main) == [Self.btcCategory, Self.scamCategory])
        let source = await overviewSource(container, overrides: [
            TokenPricingOverrideSnapshot(assetId: Self.btc, alwaysShow: true)
        ])
        #expect(source?.firstRealSnapshotDate == Self.firstReal)
        #expect(assetIDs(source) == [Self.btc, Self.scam])
    }

    // MARK: - The global and the account branch

    @Test func `the readers leave out an ignored asset in the global and the account branch`() async throws {
        let container = try makeContainer()
        try seed(container.mainContext)
        let overrides = try ignore([Self.scam], in: container.mainContext)

        let global = try await estimate(container)
        let account = try await estimate(container, accountId: Self.main)
        let globalCategories = try await categoryIDs(container)
        let accountCategories = try await categoryIDs(container, accountId: Self.main)
        let source = await overviewSource(container, overrides: overrides)
        #expect(source?.firstRealSnapshotDate == Self.firstReal)

        #expect(global == [150_000, 150_000, 150_000])
        #expect(account == [50000, 50000, 50000])
        #expect(globalCategories == [Self.btcCategory])
        #expect(accountCategories == [Self.btcCategory])
        #expect(assetIDs(source) == [Self.btc])
    }

    /// Already filtered today: the panel reads through `visibleAssetIDs`, and the current
    /// valuation never makes an ignored asset visible. Before the ignore, SCAM's category shows.
    @Test func `the bottom panel leaves out an ignored asset`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seed(context)
        let btc = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.id == Self.btc })
        let scam = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.id == Self.scam })
        let account = Account(id: Self.main, name: "Main", kind: .manual, dataSource: .manual)
        account.positions = [Position(positionType: .idle, tokens: [
            PositionToken(role: .balance, amount: 1, usdValue: 50000, asset: btc),
            PositionToken(role: .balance, amount: 1000, usdValue: 5000, asset: scam)
        ], account: account)]
        context.insert(account)
        try context.save()

        let unignored = try await load(container, mode: .value).bottomPanel.categoryChanges.map(\.id)
        #expect(Set(unignored) == [Self.btcCategory, Self.scamCategory])

        try ignore([Self.scam], in: context)
        let changes = try await load(container, mode: .value).bottomPanel.categoryChanges.map(\.id)

        #expect(changes == [Self.btcCategory])
    }

    @Test func `the readers return nothing when every row is ignored`() async throws {
        let container = try makeContainer()
        try seed(container.mainContext)
        let overrides = try ignore([Self.btc, Self.scam], in: container.mainContext)

        let global = try await estimate(container)
        let account = try await estimate(container, accountId: Self.main)
        let globalCategories = try await categoryIDs(container)
        let accountCategories = try await categoryIDs(container, accountId: Self.main)
        let source = await overviewSource(container, overrides: overrides)

        #expect(global.isEmpty)
        #expect(account.isEmpty)
        #expect(globalCategories.isEmpty)
        #expect(accountCategories.isEmpty)
        #expect(source == nil)
    }

    /// The rows exist before the override does, as they would for an asset ignored today.
    /// Un-ignoring makes them readable again (N2), with nothing backfilled.
    @Test func `an asset ignored after its rows were recorded drops out and comes back once un-ignored`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seed(context)
        let override = TokenPricingOverride(assetId: Self.scam, isIgnored: true)
        context.insert(override)
        try context.save()

        let ignoredEstimate = try await estimate(container)
        let ignoredCategories = try await categoryIDs(container)
        let ignoredSource = await overviewSource(container, overrides: [TokenPricingOverrideSnapshot(override)])
        #expect(ignoredEstimate == [150_000, 150_000, 150_000])
        #expect(ignoredCategories == [Self.btcCategory])
        #expect(assetIDs(ignoredSource) == [Self.btc])

        override.isIgnored = false
        try context.save()

        #expect(try await estimate(container) == [155_000, 155_000, 155_000])
        #expect(try await categoryIDs(container) == [Self.btcCategory, Self.scamCategory])
        let restored = await overviewSource(container, overrides: [TokenPricingOverrideSnapshot(override)])
        #expect(assetIDs(restored) == [Self.btc, Self.scam])
    }

    // MARK: - Limit-1 probes

    /// The only row before the chart start is ignored, so the earliest row that counts is Jan 5
    /// and the estimate runs. Unfiltered, the probe finds Dec 30 and both estimates give up.
    @Test func `both earliest-row probes skip an ignored row before the chart start`() async throws {
        let container = try makeContainer()
        try seed(container.mainContext, earlyIgnoredRow: true)
        let overrides = try ignore([Self.scam], in: container.mainContext)

        let global = try await estimate(container)
        let account = try await estimate(container, accountId: Self.main)
        let source = await overviewSource(container, overrides: overrides)

        #expect(global == [150_000, 150_000, 150_000])
        #expect(account == [50000, 50000, 50000])
        #expect(source?.firstRealSnapshotDate == Self.firstReal)
        #expect(assetIDs(source) == [Self.btc])
    }

    // MARK: - Large ignored lists

    @Test func `the readers leave out ignored assets among a few thousand ignored IDs`() async throws {
        let container = try makeContainer()
        try seed(container.mainContext, earlyIgnoredRow: true)
        let overrides = try ignore([Self.scam], extra: 3000, in: container.mainContext)

        let global = try await estimate(container)
        let account = try await estimate(container, accountId: Self.main)
        let globalCategories = try await categoryIDs(container)
        let source = await overviewSource(container, overrides: overrides)

        #expect(global == [150_000, 150_000, 150_000])
        #expect(account == [50000, 50000, 50000])
        #expect(globalCategories == [Self.btcCategory])
        #expect(source?.firstRealSnapshotDate == Self.firstReal)
        #expect(assetIDs(source) == [Self.btc])
    }

    /// AGENT-DECIDED 16: the same reads on the production schema in a store on disk, first with no
    /// ignored IDs, then with 5,000.
    @Test func `a disk-backed full-schema store reads with an empty and a large ignored list`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "IgnoredAssetSnapshotReaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerFactory(storeURL: directory.appending(path: "Portu.store"))
            .makeForProduction()
        try seed(container.mainContext, earlyIgnoredRow: true)

        // Unfiltered, the Dec 30 row predates the chart start, so neither estimate runs.
        #expect(try await estimate(container).isEmpty)
        #expect(try await estimate(container, accountId: Self.main).isEmpty)
        #expect(try await categoryIDs(container) == [Self.btcCategory, Self.scamCategory])
        #expect(await overviewSource(container, overrides: []) == nil)

        let overrides = try ignore([Self.scam], extra: 5000, in: container.mainContext)
        let global = try await estimate(container)
        let account = try await estimate(container, accountId: Self.main)
        let globalCategories = try await categoryIDs(container)
        let source = await overviewSource(container, overrides: overrides)

        #expect(global == [150_000, 150_000, 150_000])
        #expect(account == [50000, 50000, 50000])
        #expect(globalCategories == [Self.btcCategory])
        #expect(source?.firstRealSnapshotDate == Self.firstReal)
        #expect(assetIDs(source) == [Self.btc])
    }

    // MARK: - Query cost

    /// 10,000 rows on disk (50 assets × 2 accounts × 100 days from Jan 5) plus one ignored row on
    /// Dec 30, then 5,000 ignored IDs covering the 25 SPAM assets. Each kept ETH row is worth 1 at a
    /// flat close of 1, so an estimated day is 50 globally and 25 per account. The durations are
    /// logged for the record, measured around calls that run on the model actors; only the
    /// results are asserted.
    @Test func `reads over ten thousand rows and five thousand ignored IDs stay correct and log their cost`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "IgnoredAssetSnapshotReaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerFactory(storeURL: directory.appending(path: "Portu.store"))
            .makeForProduction()
        let context = container.mainContext
        let keepCategory = PortfolioCategoryResolver.defaults.resolve(symbol: "ETH", legacyCategory: .major).id.uuidString
        try #require(keepCategory != PortfolioCategoryResolver.defaults.resolve(symbol: "SPAM", legacyCategory: .other).id.uuidString)

        let keep = (0 ..< 25).map { _ in UUID() }
        let spam = (0 ..< 25).map { _ in UUID() }
        for (index, assetID) in keep.enumerated() {
            context.insert(Asset(id: assetID, symbol: "ETH", name: "Keep \(index)", coinGeckoId: "keep-\(index)", category: .major))
            for day in 2 ... 4 {
                context.insert(HistoricalPricePoint(coinGeckoId: "keep-\(index)", day: Self.utcDate(2024, 1, day), usdPrice: 1))
            }
        }
        for (index, assetID) in spam.enumerated() {
            context.insert(Asset(id: assetID, symbol: "SPAM", name: "Spam \(index)", coinGeckoId: "spam-\(index)", category: .other))
        }
        for day in 0 ..< 100 {
            let timestamp = Self.firstReal.addingTimeInterval(TimeInterval(day) * 86400)
            let batch = UUID()
            for accountID in [Self.main, Self.other] {
                for assetID in keep {
                    context.insert(AssetSnapshot(
                        syncBatchId: batch, timestamp: timestamp, accountId: accountID, assetId: assetID,
                        symbol: "ETH", category: .major, amount: 1, usdValue: 1))
                }
                for assetID in spam {
                    context.insert(AssetSnapshot(
                        syncBatchId: batch, timestamp: timestamp, accountId: accountID, assetId: assetID,
                        symbol: "SPAM", category: .other, amount: 1000, usdValue: 10))
                }
            }
        }
        context.insert(AssetSnapshot(
            syncBatchId: UUID(), timestamp: Self.earlyIgnored, accountId: Self.main, assetId: spam[0],
            symbol: "SPAM", category: .other, amount: 1000, usdValue: 10))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<AssetSnapshot>()) == 10001)

        let clock = ContinuousClock()
        func timed<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
            let start = clock.now
            let result = try await body()
            print("C-S timing: \(label): \(clock.now - start)")
            return result
        }

        // A discarded load after each save, so the first timed call doesn't carry the store's
        // warm-up. Baseline with nothing ignored: the Dec 30 row stops both estimates before
        // their day fetch, so only the assets and Overview lines compare like for like.
        _ = try await estimate(container)
        _ = try await timed("performance global, value, 0 ignored") { try await estimate(container) }
        _ = try await timed("performance account, value, 0 ignored") { try await estimate(container, accountId: Self.main) }
        _ = try await timed("performance global, assets, 0 ignored") { try await categoryIDs(container) }
        _ = try await timed("performance account, assets, 0 ignored") { try await categoryIDs(container, accountId: Self.main) }
        _ = await timed("overview estimate, 0 ignored") { await overviewSource(container, overrides: []) }

        let overrides = try ignore(spam, extra: 5000 - spam.count, in: context)
        try #require(overrides.count == 5000)
        _ = try await estimate(container)
        let global = try await timed("performance global, value, 5000 ignored") { try await estimate(container) }
        let account = try await timed("performance account, value, 5000 ignored") {
            try await estimate(container, accountId: Self.main)
        }
        let globalCategories = try await timed("performance global, assets, 5000 ignored") { try await categoryIDs(container) }
        let accountCategories = try await timed("performance account, assets, 5000 ignored") {
            try await categoryIDs(container, accountId: Self.main)
        }
        let source = await timed("overview estimate, 5000 ignored") { await overviewSource(container, overrides: overrides) }

        #expect(global == [50, 50, 50])
        #expect(account == [25, 25, 25])
        #expect(globalCategories == [keepCategory])
        #expect(accountCategories == [keepCategory])
        #expect(source?.firstRealSnapshotDate == Self.firstReal)
        #expect(assetIDs(source) == Set(keep))
        #expect(source?.firstDayEntries.count == 50)
    }
}
