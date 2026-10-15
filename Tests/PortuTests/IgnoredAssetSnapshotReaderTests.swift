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
    private static let pending: Comment = "AssetSnapshot readers leave ignored assets out in the next commit"

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

        withKnownIssue(Self.pending) {
            #expect(global == [150_000, 150_000, 150_000])
            #expect(account == [50000, 50000, 50000])
            #expect(globalCategories == [Self.btcCategory])
            #expect(accountCategories == [Self.btcCategory])
            #expect(assetIDs(source) == [Self.btc])
        }
    }

    /// Already filtered today: the panel reads through `visibleAssetIDs`, and the current
    /// valuation never makes an ignored asset visible.
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

        withKnownIssue(Self.pending) {
            #expect(global.isEmpty)
            #expect(account.isEmpty)
            #expect(globalCategories.isEmpty)
            #expect(accountCategories.isEmpty)
            #expect(source == nil)
        }
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
        withKnownIssue(Self.pending) {
            #expect(ignoredEstimate == [150_000, 150_000, 150_000])
            #expect(ignoredCategories == [Self.btcCategory])
            #expect(assetIDs(ignoredSource) == [Self.btc])
        }

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

        withKnownIssue(Self.pending) {
            #expect(global == [150_000, 150_000, 150_000])
            #expect(account == [50000, 50000, 50000])
            #expect(source?.firstRealSnapshotDate == Self.firstReal)
            #expect(assetIDs(source) == [Self.btc])
        }
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

        withKnownIssue(Self.pending) {
            #expect(global == [150_000, 150_000, 150_000])
            #expect(account == [50000, 50000, 50000])
            #expect(globalCategories == [Self.btcCategory])
            #expect(source?.firstRealSnapshotDate == Self.firstReal)
            #expect(assetIDs(source) == [Self.btc])
        }
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

        withKnownIssue(Self.pending) {
            #expect(global == [150_000, 150_000, 150_000])
            #expect(account == [50000, 50000, 50000])
            #expect(globalCategories == [Self.btcCategory])
            #expect(source?.firstRealSnapshotDate == Self.firstReal)
            #expect(assetIDs(source) == [Self.btc])
        }
    }
}
