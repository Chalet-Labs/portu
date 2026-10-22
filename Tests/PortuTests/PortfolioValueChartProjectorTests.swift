import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// The value chart's build and conversion against the chart's in-view pipeline on master (#124,
/// spec C1–C3). One store holds four snapshots in the month, USD→EUR and USD→CHF rate rows with a
/// second, later row on one day each (EUR day −10, CHF day −9) and an EUR row before the month,
/// USD and CHF closes, and asset rows whose earliest belongs to an ignored asset.
///
/// The estimate holds BTC 1 (60,000) and ETH 2 (5,000) from the day −20 batch, at flat USD closes
/// of 60,000 and 2,500 on days −29 to −20, so each estimated day is 65,000. A SCAM row on day −25
/// predates it but is ignored; a CHF close of 70,000 on day −25 must not price it.
@MainActor
struct PortfolioValueChartProjectorTests {
    typealias Fixture = PortfolioValuationFixture

    /// 2025-10-06 12:00 UTC: the chart starts 2025-09-06, day −30.
    static let now = Fixture.noon(0)
    private static let liveEURRate = Fixture.decimal("0.95")
    static let account = id(10)
    static let btc = id(1)
    static let eth = id(2)
    private static let scam = id(3)

    // MARK: - Source (C1)

    @Test func `the source equals the chart's in-view pipeline`() async throws {
        let container = try Self.seededStore()

        let source = try await Self.build(container)

        let today = try await Self.todaysPipeline(container)
        #expect(source == today.source)
        #expect(PortfolioValueChartData.converting(source, currency: .eur, usdToDisplayRate: Self.liveEURRate, today: Self.now) == today.eur)
        #expect(source.snapshots.map(\.timestamp) == [Fixture.noon(-20), Fixture.noon(-10), Fixture.noon(-9), Fixture.noon(-1)])
        #expect(source.rates.count == 9, "every row from the chart start's day on; the EUR row before it is left out")
        #expect(source.estimatedUSD.map(\.date) == (-29 ... -21).map(Fixture.day), "the days with closes before the first asset batch")
        #expect(source.estimatedUSD.allSatisfy { $0.value == 65000 }, "BTC and ETH; neither the ignored SCAM row nor the CHF close")
    }

    /// The month filter leaves the older snapshot out, and the recorded series now starts before
    /// the chart does, so the estimate ends before it starts (U7), as on master.
    @Test func `a snapshot before the month is left out and leaves no estimate as the chart's pipeline did`() async throws {
        let container = try Self.seededStore()
        container.mainContext.insert(Self.snapshot(at: Fixture.noon(-40), total: 50000))
        try container.mainContext.save()

        let source = try await Self.build(container)

        #expect(try await source == Self.todaysPipeline(container).source)
        #expect(source.snapshots.first?.timestamp == Fixture.noon(-20))
        #expect(source.estimatedUSD.isEmpty)
    }

    @Test func `a day with two rate rows converts with the later one in every quote currency`() async throws {
        let container = try Self.seededStore()

        let source = try await Self.build(container)
        let eur = PortfolioValueChartData.converting(source, currency: .eur, usdToDisplayRate: Self.liveEURRate, today: Self.now)
        let chf = PortfolioValueChartData.converting(source, currency: .chf, usdToDisplayRate: Fixture.decimal("0.85"), today: Self.now)

        #expect(Set(source.rates.map(\.quoteCurrency)) == [.eur, .chf])
        #expect(source.rates.count(where: { $0.quoteCurrency == .eur }) == 5, "two rows on day −10")
        #expect(source.rates.count(where: { $0.quoteCurrency == .chf }) == 4, "two rows on day −9")
        #expect(Self.value(at: Fixture.noon(-10), in: eur) == 60812, "66,100 at the later EUR row, 0.92")
        #expect(Self.value(at: Fixture.noon(-9), in: chf) == 54120, "66,000 at the later CHF row, 0.82")
    }

    @Test func `with backfill off the source has no estimate and the same series`() async throws {
        let container = try Self.seededStore()

        let on = try await Self.build(container, isBackfillEnabled: true)
        let off = try await Self.build(container, isBackfillEnabled: false)

        #expect(!on.estimatedUSD.isEmpty, "the store has an estimate to leave out")
        #expect(off.estimatedUSD.isEmpty)
        #expect(off.snapshots == on.snapshots)
        #expect(off.rates == on.rates)
    }

    // MARK: - Conversion (C3)

    /// Day 0 is today until 23:59:59 UTC and takes the live rate; from 00:00:01 it is a past day
    /// and takes its row. A day with no EUR row takes the live rate, and a CHF row never applies.
    @Test func `conversion uses the live rate for today's UTC day and the day's row before it`() {
        let source = PortfolioValueChartSource(
            snapshots: [
                PortfolioValueSnapshotPoint(id: Self.id(1), timestamp: Fixture.noon(-1), totalValueUSD: 1000, isPartial: false),
                PortfolioValueSnapshotPoint(id: Self.id(2), timestamp: Fixture.noon(0), totalValueUSD: 2000, isPartial: true)
            ],
            rates: [
                Self.rateEntry(.eur, Fixture.day(-2), "0.80"),
                Self.rateEntry(.chf, Fixture.day(-1), "0.70"),
                Self.rateEntry(.eur, Fixture.day(-1), "0.90"),
                Self.rateEntry(.eur, Fixture.day(0), "0.91")
            ],
            estimatedUSD: [
                HistoricalPortfolioValuePoint(date: Fixture.day(-3), value: 300, kind: .estimated),
                HistoricalPortfolioValuePoint(date: Fixture.day(-2), value: 500, kind: .estimated)
            ])
        let estimated = [
            HistoricalPortfolioValuePoint(date: Fixture.day(-3), value: 285, kind: .estimated),
            HistoricalPortfolioValuePoint(date: Fixture.day(-2), value: 400, kind: .estimated)
        ]

        let lastSecond = PortfolioValueChartData.converting(
            source, currency: .eur, usdToDisplayRate: Self.liveEURRate, today: Fixture.day(1).addingTimeInterval(-1))
        let firstSecond = PortfolioValueChartData.converting(
            source, currency: .eur, usdToDisplayRate: Self.liveEURRate, today: Fixture.day(1).addingTimeInterval(1))

        #expect(lastSecond == PortfolioValueChartData(
            currencyCode: "EUR",
            snapshots: [
                PortfolioValueChartPoint(id: Self.id(1), timestamp: Fixture.noon(-1), value: 900, isPartial: false),
                PortfolioValueChartPoint(id: Self.id(2), timestamp: Fixture.noon(0), value: 1900, isPartial: true)
            ],
            estimated: estimated))
        #expect(firstSecond == PortfolioValueChartData(
            currencyCode: "EUR",
            snapshots: [
                PortfolioValueChartPoint(id: Self.id(1), timestamp: Fixture.noon(-1), value: 900, isPartial: false),
                PortfolioValueChartPoint(id: Self.id(2), timestamp: Fixture.noon(0), value: 1820, isPartial: true)
            ],
            estimated: estimated))
    }

    /// The source keeps every quote currency, so switching from USD to EUR converts the same source:
    /// a past day with an EUR row takes it, a day without one takes the live rate.
    @Test func `a switch from USD to EUR converts past points with the source's EUR rows`() async throws {
        let container = try Self.seededStore()
        let source = try await Self.build(container)

        let usd = PortfolioValueChartData.converting(source, currency: .usd, usdToDisplayRate: 1, today: Self.now)
        let eur = PortfolioValueChartData.converting(source, currency: .eur, usdToDisplayRate: Self.liveEURRate, today: Self.now)

        #expect(usd.currencyCode == "USD")
        #expect(usd.snapshots.map(\.value) == source.snapshots.map(\.totalValueUSD))
        #expect(usd.estimated == source.estimatedUSD)
        #expect(eur.currencyCode == "EUR")
        #expect(eur.snapshots.map(\.value) == [61750, 60812, 62700, 62310], "live 0.95 on days −20 and −9; rows 0.92 and 0.93 on days −10 and −1")
        #expect(eur.estimated.allSatisfy { $0.value == 61750 }, "no EUR row on an estimated day: the live rate")
    }

    // MARK: - Build (C2)

    /// Production keeps one chart projector, and so one model context, for the app's life
    /// (`PortfolioValueChartProjectorClient.live`). Rows other contexts change in place after it has
    /// read them must show in its next build: a rate refreshed, an asset ignored, a sync's snapshot.
    @Test func `one long lived projector sees rows another context updates`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PortfolioValueChartProjectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try Self.seededStore(at: directory.appendingPathComponent("Portu.store"))
        let client = PortfolioValueChartProjectorClient.live(modelContainer: container)
        let request = Self.request()
        let before = try await client.build(request)

        let context = container.mainContext
        let rates = try context.fetch(FetchDescriptor<CurrencyConversionRatePoint>())
        let overrides = try context.fetch(FetchDescriptor<TokenPricingOverride>())
        let eurRow = try #require(rates.first { $0.quoteCurrency == .eur && $0.day == Fixture.day(-1) })
        eurRow.update(rate: Fixture.decimal("0.99"), fetchedAt: Self.now)
        try #require(overrides.first { $0.assetId == Self.eth }).isIgnored = true
        let synced = Fixture.noon(0).addingTimeInterval(-3600)
        context.insert(Self.snapshot(at: synced, total: 68000))
        try context.save()
        let after = try await client.build(request)

        #expect(Self.eurRate(on: Fixture.day(-1), in: before) == Fixture.decimal("0.93"))
        #expect(Self.eurRate(on: Fixture.day(-1), in: after) == Fixture.decimal("0.99"), "the refreshed rate is seen")
        #expect(before.estimatedUSD.allSatisfy { $0.value == 65000 })
        #expect(!after.estimatedUSD.isEmpty)
        #expect(after.estimatedUSD.allSatisfy { $0.value == 60000 }, "ETH, ignored in place, leaves the estimate")
        #expect(after.snapshots.map(\.timestamp) == before.snapshots.map(\.timestamp) + [synced], "the new snapshot is seen")
    }

    @Test func `the client factory keeps the chart projector off the main thread`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let projector = await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)

        #expect(await projector.isExecutingOnMainThread() == false)
    }

    /// The chart projector has its own queue: with its executor held, as a long chart build would
    /// hold it, a holdings projector is created and builds on the same container meanwhile. A
    /// holdings build stuck behind it fails after 30 s instead of hanging. The hold is detached: a
    /// task that inherits the main actor ran the hold on the main thread (seen in a sample) and
    /// blocked the test itself.
    @Test func `a chart build held open does not delay a holdings build`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let request = Self.request()
        let chart = await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)
        try #require(await chart.isExecutingOnMainThread() == false, "holding the main thread would hang the test")
        let release = DispatchSemaphore(value: 0)
        let (held, holding) = AsyncStream.makeStream(of: Void.self)
        let hold = Task.detached { await chart.holdExecutor(until: release) { holding.yield() } }
        for await _ in held {
            break
        }

        let holdingsBuilt = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let projector = await PortfolioProjectorClient.makeProjector(modelContainer: container)
                _ = try? await projector.build(request)
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return false
            }
            let first = await group.next() ?? false
            release.signal()
            group.cancelAll()
            return first
        }
        await hold.value

        #expect(holdingsBuilt)
    }

    @Test func `a build cancelled before it starts reads nothing and throws`() async throws {
        let container = try Self.seededStore()
        let projector = await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)
        let request = Self.request()

        let task = Task { try await projector.build(request) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func `the default live client reports a missing container instead of trapping`() async {
        let request = Self.request()

        await #expect(throws: PortfolioProjectorError(
            message: "PortfolioValueChartProjectorClient.liveValue must be overridden at Store creation")) {
            _ = try await PortfolioValueChartProjectorClient.liveValue.build(request)
        }
    }

    // MARK: - Today's pipeline

    /// What the chart computed on master over the same store: the `@Query`s from its `init()`, the
    /// month filter of `filteredSnapshots`, `estimateInputs` and `reloadEstimatedPoints` with
    /// backfill on, and `convertedSnapshots` in EUR at `liveEURRate`, with `now` as today.
    private static func todaysPipeline(
        _ container: ModelContainer) async throws -> (source: PortfolioValueChartSource, eur: PortfolioValueChartData) {
        let context = container.mainContext
        let chartStart = ChartTimeRange.oneMonth.startDate(at: now)
        let historicalStartDate = HistoricalPriceCalendar.utcStartOfDay(for: chartStart)
        let snapshots = try context.fetch(FetchDescriptor<PortfolioSnapshot>(sortBy: [SortDescriptor(\.timestamp)]))
            .filter { $0.timestamp >= chartStart }
        let rates = try context.fetch(FetchDescriptor<CurrencyConversionRatePoint>(
            predicate: #Predicate { $0.day >= historicalStartDate },
            sortBy: [SortDescriptor(\.day)]))
        let prices = try context.fetch(FetchDescriptor<HistoricalPricePoint>(
            predicate: #Predicate { $0.day >= historicalStartDate },
            sortBy: [SortDescriptor(\.day)]))
            .compactMap { point -> HistoricalPriceEntry? in
                guard point.fiatCurrency == .usd, point.day >= historicalStartDate else { return nil }
                return HistoricalPriceEntry(coinGeckoId: point.coinGeckoId, day: point.day, usdPrice: point.usdPrice)
            }
        let overrides = try context.fetch(FetchDescriptor<TokenPricingOverride>()).map(TokenPricingOverrideSnapshot.init)
        let estimate = await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)
            .estimateSource(overrides: overrides, chartStartDate: chartStart)
        let estimatedUSD = estimate.map {
            PortfolioValueChartFeature.estimatedPoints(source: $0, prices: prices, chartStartDate: chartStart, isBackfillEnabled: true)
        } ?? []
        let conversion = CurrencyConversionContext(displayCurrency: .eur, currentUSDToDisplayRate: liveEURRate, historicalRatePoints: rates)

        let source = PortfolioValueChartSource(
            snapshots: snapshots.map {
                PortfolioValueSnapshotPoint(id: $0.id, timestamp: $0.timestamp, totalValueUSD: $0.totalValue, isPartial: $0.isPartial)
            },
            rates: rates.map(CurrencyConversionRateEntry.init),
            estimatedUSD: estimatedUSD)
        let eur = PortfolioValueChartData(
            currencyCode: "EUR",
            snapshots: snapshots.map {
                PortfolioValueChartPoint(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    value: conversion.convertUSDValue($0.totalValue, on: $0.timestamp, today: now),
                    isPartial: $0.isPartial)
            },
            estimated: estimatedUSD.map { conversion.convertUSDPoint($0, today: now) })
        return (source, eur)
    }

    // MARK: - Fixture

    static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()
    }

    static func request(isBackfillEnabled: Bool = true) -> PortfolioProjectionRequest {
        PortfolioProjectionRequest(isHistoricalBackfillEnabled: isBackfillEnabled, now: now)
    }

    static func build(_ container: ModelContainer, isBackfillEnabled: Bool = true) async throws -> PortfolioValueChartSource {
        let projector = await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)
        return try await projector.build(request(isBackfillEnabled: isBackfillEnabled))
    }

    private static func value(at timestamp: Date, in data: PortfolioValueChartData) -> Decimal? {
        data.snapshots.first { $0.timestamp == timestamp }?.value
    }

    private static func eurRate(on day: Date, in source: PortfolioValueChartSource) -> Decimal? {
        source.rates.first { $0.quoteCurrency == .eur && $0.day == day }?.rate
    }

    private static func rateEntry(_ quote: FiatCurrency, _ day: Date, _ rate: String) -> CurrencyConversionRateEntry {
        CurrencyConversionRateEntry(baseCurrency: .usd, quoteCurrency: quote, day: day, rate: Fixture.decimal(rate))
    }

    private static func rateRow(_ quote: FiatCurrency, _ day: Date, _ rate: String) -> CurrencyConversionRatePoint {
        CurrencyConversionRatePoint(baseCurrency: .usd, quoteCurrency: quote, day: day, rate: Fixture.decimal(rate))
    }

    /// A second row for a day already stored, later that day under its own cache key: the duplicate
    /// `CurrencyConversionRateCacheWriter` removes when it next writes that day.
    private static func laterRateRow(_ quote: FiatCurrency, _ time: Date, _ rate: String) -> CurrencyConversionRatePoint {
        let row = rateRow(quote, time, rate)
        row.day = time
        row.cacheKey += ":later"
        return row
    }

    static func snapshot(at timestamp: Date, total: Decimal, isPartial: Bool = false) -> PortfolioSnapshot {
        PortfolioSnapshot(
            syncBatchId: UUID(),
            timestamp: timestamp,
            totalValue: total,
            idleValue: total,
            deployedValue: 0,
            debtValue: 0,
            isPartial: isPartial)
    }

    static func assetRow(_ asset: UUID, _ symbol: String, at timestamp: Date, amount: Decimal, usdValue: Decimal) -> AssetSnapshot {
        AssetSnapshot(
            syncBatchId: UUID(),
            timestamp: timestamp,
            accountId: account,
            assetId: asset,
            symbol: symbol,
            category: .major,
            amount: amount,
            usdValue: usdValue)
    }

    /// The seeded store, in memory, or in an SQLite file at `url` as production keeps it.
    static func seededStore(at url: URL? = nil) throws -> ModelContainer {
        let container = if let url {
            try ModelContainer(
                for: ModelContainerFactory.schema,
                configurations: [ModelConfiguration(schema: ModelContainerFactory.schema, url: url)])
        } else {
            try ModelContainerFactory().makeInMemory()
        }
        let context = container.mainContext
        context.insert(Asset(id: btc, symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major))
        context.insert(Asset(id: eth, symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major))
        context.insert(Asset(id: scam, symbol: "SCAM", name: "Scam", coinGeckoId: "scam-token", category: .other))
        context.insert(TokenPricingOverride(assetId: scam, isIgnored: true))
        context.insert(TokenPricingOverride(assetId: eth, alwaysShow: true))

        context.insert(assetRow(scam, "SCAM", at: Fixture.noon(-25), amount: 1000, usdValue: 100))
        context.insert(assetRow(btc, "BTC", at: Fixture.noon(-20), amount: 1, usdValue: 60000))
        context.insert(assetRow(eth, "ETH", at: Fixture.noon(-20), amount: 2, usdValue: 5000))
        context.insert(assetRow(btc, "BTC", at: Fixture.noon(-10), amount: 1, usdValue: 61000))
        context.insert(assetRow(eth, "ETH", at: Fixture.noon(-10), amount: 2, usdValue: 5100))

        context.insert(snapshot(at: Fixture.noon(-20), total: 65000))
        context.insert(snapshot(at: Fixture.noon(-10), total: 66100))
        context.insert(snapshot(at: Fixture.noon(-9), total: 66000, isPartial: true))
        context.insert(snapshot(at: Fixture.noon(-1), total: 67000))

        for row in [
            rateRow(.eur, Fixture.day(-35), "0.80"),
            rateRow(.eur, Fixture.day(-12), "0.88"),
            rateRow(.chf, Fixture.day(-11), "0.78"),
            rateRow(.eur, Fixture.day(-10), "0.90"),
            laterRateRow(.eur, Fixture.day(-10).addingTimeInterval(6 * 3600), "0.92"),
            rateRow(.chf, Fixture.day(-9), "0.80"),
            laterRateRow(.chf, Fixture.day(-9).addingTimeInterval(6 * 3600), "0.82"),
            rateRow(.chf, Fixture.day(-2), "0.84"),
            rateRow(.eur, Fixture.day(-1), "0.93"),
            rateRow(.eur, Fixture.day(0), "0.94")
        ] {
            context.insert(row)
        }

        for offset in -29 ... -20 {
            context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Fixture.day(offset), usdPrice: 60000))
            context.insert(HistoricalPricePoint(coinGeckoId: "ethereum", day: Fixture.day(offset), usdPrice: 2500))
            context.insert(HistoricalPricePoint(coinGeckoId: "scam-token", day: Fixture.day(offset), usdPrice: 1))
        }
        context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Fixture.day(-40), usdPrice: 59000))
        context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Fixture.day(-15), usdPrice: 64000))
        context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Fixture.day(-25), currency: .chf, price: 70000))
        try context.save()
        return container
    }
}
