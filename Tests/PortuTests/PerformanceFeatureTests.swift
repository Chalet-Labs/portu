// swiftlint:disable file_length

import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct PerformanceFeatureTests {
    // MARK: - Account Filter

    @Test func `account filter updates state`() async {
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        }

        let id = UUID()
        await store.send(.accountSelected(id)) {
            $0.selectedAccountId = id
        }
        await store.send(.accountSelected(nil)) {
            $0.selectedAccountId = nil
        }
    }

    // MARK: - Time Range

    @Test func `time range updates state`() async {
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        }

        await store.send(.timeRangeChanged(.oneYear)) {
            $0.selectedRange = .oneYear
        }
        await store.send(.timeRangeChanged(.ytd)) {
            $0.selectedRange = .ytd
        }
    }

    // MARK: - Chart Mode

    @Test func `chart mode updates state`() async {
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        }

        await store.send(.chartModeChanged(.assets)) {
            $0.chartMode = .assets
        }
        await store.send(.chartModeChanged(.valueChange)) {
            $0.chartMode = .valueChange
        }
        await store.send(.chartModeChanged(.value)) {
            $0.chartMode = .value
        }
    }

    // MARK: - Category Toggle

    @Test func `portfolio category toggle adds and removes`() async {
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        }

        let btc = PortfolioCategoryDefaults.btcCategoryID.uuidString
        let eth = PortfolioCategoryDefaults.ethCategoryID.uuidString

        await store.send(.portfolioCategoryToggled(btc)) {
            $0.disabledPortfolioCategoryIDs = [btc]
        }
        await store.send(.portfolioCategoryToggled(eth)) {
            $0.disabledPortfolioCategoryIDs = [btc, eth]
        }
        await store.send(.portfolioCategoryToggled(btc)) {
            $0.disabledPortfolioCategoryIDs = [eth]
        }
    }

    // MARK: - Cumulative Toggle

    @Test func `cumulative toggle updates state`() async {
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        }

        await store.send(.showCumulativeToggled) {
            $0.showCumulative = true
        }
        await store.send(.showCumulativeToggled) {
            $0.showCumulative = false
        }
    }
}

// MARK: - Last Per Day

struct PerformanceLastPerDayTests {
    private let cal = Calendar.current

    @Test func `keeps last value per day`() throws {
        let noon = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 12)))
        let evening = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 20)))
        let nextDay = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 16, hour: 10)))

        let values: [(Date, Decimal)] = [
            (noon, 1000),
            (evening, 1200), // same day, later → keep this
            (nextDay, 1300)
        ]

        let result = PerformanceFeature.lastPerDay(values)

        #expect(result.count == 2)
        #expect(result[0].1 == 1200) // evening value for day 15
        #expect(result[1].1 == 1300) // day 16
    }

    @Test func `returns sorted by date ascending`() throws {
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 16, hour: 12)))
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 12)))

        let result = PerformanceFeature.lastPerDay([(day2, 200), (day1, 100)])

        #expect(result[0].0 < result[1].0)
    }

    @Test func `empty input returns empty`() {
        let result = PerformanceFeature.lastPerDay([])
        #expect(result.isEmpty)
    }
}

// MARK: - Value Change Bar Computation

struct PerformanceValueChangeTests {
    @Test func `snapshot delta mode is labeled value change`() {
        #expect(PerformanceChartMode.allCases.map(\.rawValue) == [
            "Value",
            "Assets",
            "Value Change",
            "PnL"
        ])
    }

    @Test func `computes daily and cumulative value change`() throws {
        let cal = Calendar.current
        let d1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let d2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let d3 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 12)))

        let daily: [(Date, Decimal)] = [(d1, 1000), (d2, 1100), (d3, 1050)]

        let bars = PerformanceFeature.computeValueChangeBars(from: daily)

        #expect(bars.count == 2) // first day is baseline
        #expect(bars[0].change == 100) // 1100 - 1000
        #expect(bars[0].cumulative == 100)
        #expect(bars[1].change == -50) // 1050 - 1100
        #expect(bars[1].cumulative == 50) // 100 + (-50)
    }

    @Test func `fewer than 2 days returns empty`() throws {
        let cal = Calendar.current
        let d1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))

        let bars = PerformanceFeature.computeValueChangeBars(from: [(d1, 1000)])

        #expect(bars.isEmpty)
    }

    @Test func `empty returns empty`() {
        let values: [(Date, Decimal)] = []
        let bars = PerformanceFeature.computeValueChangeBars(from: values)
        #expect(bars.isEmpty)
    }

    @Test func `converts daily values before computing value change`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let d1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let d2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let d3 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 12)))
        let context = try CurrencyConversionContext(
            displayCurrency: .eur,
            currentUSDToDisplayRate: 1,
            historicalUSDToDisplayRatesByDay: [
                HistoricalPriceCalendar.utcStartOfDay(for: d1): #require(Decimal(string: "0.9")),
                HistoricalPriceCalendar.utcStartOfDay(for: d2): #require(Decimal(string: "0.8")),
                HistoricalPriceCalendar.utcStartOfDay(for: d3): #require(Decimal(string: "0.7"))
            ])

        let bars = PerformanceFeature.computeValueChangeBars(
            from: [(d1, 1000), (d2, 1100), (d3, 1200)],
            conversionContext: context)

        #expect(bars.map(\.change) == [-20, -40])
        #expect(bars.map(\.cumulative) == [-20, -60])
    }

    @Test func `omits transitions adjacent to unreliable observations`() throws {
        let cal = Calendar.current
        let d1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let d2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let d3 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 12)))
        let d4 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 4, hour: 12)))

        let series = PerformanceFeature.computeValueChangeSeries(from: [
            ValueChangeObservation(date: d1, value: 1000, isReliable: true),
            ValueChangeObservation(date: d2, value: 700, isReliable: false),
            ValueChangeObservation(date: d3, value: 1100, isReliable: true),
            ValueChangeObservation(date: d4, value: 1150, isReliable: true)
        ])
        let bars = series.bars

        #expect(bars.count == 1)
        #expect(bars.first?.date == d4)
        #expect(bars.first?.change == 50)
        #expect(bars.first?.cumulative == 50)
        #expect(series.hasSkippedTransitions)
    }

    @Test func `daily dedup keeps reliability from the latest observation`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let morning = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 8)))
        let evening = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 20)))

        let daily = PerformanceFeature.lastValueChangeObservationPerDay([
            ValueChangeObservation(date: evening, value: 900, isReliable: false),
            ValueChangeObservation(date: morning, value: 1000, isReliable: true)
        ])

        #expect(daily.count == 1)
        #expect(daily.first?.date == evening)
        #expect(daily.first?.value == 900)
        #expect(daily.first?.isReliable == false)
    }
}

// MARK: - Category Change Breakdown

struct PerformanceCategoryChangeTests {
    @MainActor
    @Test func `category snapshot entry resolves through supplied resolver`() {
        let categoryID = UUID()
        let category = PortfolioCategorySnapshot(
            id: categoryID,
            name: "Custom ETH",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let resolver = PortfolioCategoryResolver(
            categories: [category, PortfolioCategoryDefaults.fallbackCategory],
            rules: [
                CategorySymbolRuleSnapshot(
                    id: UUID(),
                    symbol: "ETH",
                    categoryId: categoryID)
            ])
        let snapshot = AssetSnapshot(
            syncBatchId: UUID(),
            timestamp: Date(),
            accountId: UUID(),
            assetId: UUID(),
            symbol: "ETH",
            category: .major,
            portfolioCategoryID: PortfolioCategoryDefaults.ethCategoryID.uuidString,
            portfolioCategoryName: "Frozen ETH",
            amount: 1,
            usdValue: 100)

        let entry = CategorySnapshotEntry(snapshot: snapshot, categoryResolver: resolver)

        #expect(entry.categoryID == categoryID.uuidString)
        #expect(entry.categoryName == "Custom ETH")
    }

    @MainActor
    @Test func `category snapshot entry maps legacy known symbols to default portfolio category IDs`() {
        let snapshot = AssetSnapshot(
            syncBatchId: UUID(),
            timestamp: Date(),
            accountId: UUID(),
            assetId: UUID(),
            symbol: "ETH",
            category: .major,
            amount: 1,
            usdValue: 2000)

        let entry = CategorySnapshotEntry(snapshot: snapshot)

        #expect(entry.categoryID == PortfolioCategoryDefaults.ethCategoryID.uuidString)
        #expect(entry.categoryName == "ETH")
    }

    @Test func `computes start end and percent change`() throws {
        let cal = Calendar.current
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))

        let acct = UUID()
        let btc = UUID()
        let usdc = UUID()
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day1, category: .major, usdValue: 1000),
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day2, category: .major, usdValue: 1200),
            CategorySnapshotEntry(accountId: acct, assetId: usdc, timestamp: day1, category: .stablecoin, usdValue: 500),
            CategorySnapshotEntry(accountId: acct, assetId: usdc, timestamp: day2, category: .stablecoin, usdValue: 500)
        ]

        let changes = PerformanceFeature.computeCategoryChanges(entries: entries)

        let major = changes.first { $0.name == "Major" }
        #expect(major?.startValue == 1000)
        #expect(major?.endValue == 1200)
        #expect(major?.percentChange == Decimal(string: "0.2")!) // 200/1000

        let stable = changes.first { $0.name == "Stablecoin" }
        #expect(stable?.percentChange == 0)
    }

    @Test func `category changes compute percentages from converted start and end values`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let acct = UUID()
        let asset = UUID()
        let context = try CurrencyConversionContext(
            displayCurrency: .chf,
            currentUSDToDisplayRate: 1,
            historicalUSDToDisplayRatesByDay: [
                HistoricalPriceCalendar.utcStartOfDay(for: day1): #require(Decimal(string: "0.5")),
                HistoricalPriceCalendar.utcStartOfDay(for: day2): #require(Decimal(string: "1.0"))
            ])

        let changes = PerformanceFeature.computeCategoryChanges(
            entries: [
                CategorySnapshotEntry(accountId: acct, assetId: asset, timestamp: day1, category: .major, usdValue: 1000),
                CategorySnapshotEntry(accountId: acct, assetId: asset, timestamp: day2, category: .major, usdValue: 1000)
            ],
            conversionContext: context)

        let major = try #require(changes.first { $0.name == "Major" })
        #expect(major.startValue == 500)
        #expect(major.endValue == 1000)
        #expect(major.percentChange == 1)
    }

    @Test func `category changes can be scoped to dashboard visible assets`() throws {
        let cal = Calendar.current
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))

        let acct = UUID()
        let hiddenBTC = UUID()
        let visibleETH = UUID()
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: acct,
                assetId: hiddenBTC,
                timestamp: day1,
                category: .major,
                categoryID: "btc",
                categoryName: "BTC",
                usdValue: 1000),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: hiddenBTC,
                timestamp: day2,
                category: .major,
                categoryID: "btc",
                categoryName: "BTC",
                usdValue: 1200),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: visibleETH,
                timestamp: day1,
                category: .major,
                categoryID: "eth",
                categoryName: "ETH",
                usdValue: 2000),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: visibleETH,
                timestamp: day2,
                category: .major,
                categoryID: "eth",
                categoryName: "ETH",
                usdValue: 2200)
        ]

        let changes = PerformanceFeature.computeCategoryChanges(
            entries: entries,
            visibleAssetIDs: [visibleETH])

        #expect(changes.map(\.name) == ["ETH"])
        #expect(changes.first?.startValue == 2000)
        #expect(changes.first?.endValue == 2200)
    }

    @Test func `uses resolved portfolio category names`() throws {
        let cal = Calendar.current
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let acct = UUID()
        let eth = UUID()

        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: acct,
                assetId: eth,
                timestamp: day1,
                category: .major,
                categoryID: PortfolioCategoryDefaults.ethCategoryID.uuidString,
                categoryName: "ETH",
                usdValue: 1000),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: eth,
                timestamp: day2,
                category: .major,
                categoryID: PortfolioCategoryDefaults.ethCategoryID.uuidString,
                categoryName: "ETH",
                usdValue: 1200)
        ]

        let chartPoints = PerformanceFeature.aggregateCategorySnapshots(entries: entries)
        let changes = PerformanceFeature.computeCategoryChanges(entries: entries)

        #expect(Set(chartPoints.map(\.categoryName)) == ["ETH"])
        #expect(changes.first?.name == "ETH")
        #expect(changes.first?.percentChange == Decimal(string: "0.2")!)
    }

    @Test func `uses category ids as stable identity when names collide`() throws {
        let cal = Calendar.current
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let acct = UUID()
        let firstAsset = UUID()
        let secondAsset = UUID()
        let firstCategoryID = "11111111-1111-1111-1111-111111111111"
        let secondCategoryID = "22222222-2222-2222-2222-222222222222"

        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: acct,
                assetId: firstAsset,
                timestamp: day1,
                category: .other,
                categoryID: firstCategoryID,
                categoryName: "Custom",
                usdValue: 100),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: firstAsset,
                timestamp: day2,
                category: .other,
                categoryID: firstCategoryID,
                categoryName: "Custom",
                usdValue: 120),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: secondAsset,
                timestamp: day1,
                category: .defi,
                categoryID: secondCategoryID,
                categoryName: "Custom",
                usdValue: 200),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: secondAsset,
                timestamp: day2,
                category: .defi,
                categoryID: secondCategoryID,
                categoryName: "Custom",
                usdValue: 240)
        ]

        let changes = PerformanceFeature.computeCategoryChanges(entries: entries)

        #expect(changes.count == 2)
        #expect(Set(changes.map(\.id)) == [firstCategoryID, secondCategoryID])
    }

    @Test func `category chart points retain ids when names collide`() throws {
        let cal = Calendar.current
        let day = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let acct = UUID()
        let firstCategoryID = "11111111-1111-1111-1111-111111111111"
        let secondCategoryID = "22222222-2222-2222-2222-222222222222"

        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: acct,
                assetId: UUID(),
                timestamp: day,
                category: .other,
                categoryID: firstCategoryID,
                categoryName: "Custom",
                usdValue: 100),
            CategorySnapshotEntry(
                accountId: acct,
                assetId: UUID(),
                timestamp: day,
                category: .defi,
                categoryID: secondCategoryID,
                categoryName: "Custom",
                usdValue: 200)
        ]

        let points = PerformanceFeature.aggregateCategorySnapshots(entries: entries)

        #expect(points.count == 2)
        #expect(Set(points.map(\.categoryID)) == [firstCategoryID, secondCategoryID])
        #expect(Set(points.map(\.categoryName)) == ["Custom"])
    }

    @Test func `category chart converts deduped values before aggregation`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let morning = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 8)))
        let evening = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 20)))
        let day = HistoricalPriceCalendar.utcStartOfDay(for: morning)
        let acct = UUID()
        let asset = UUID()
        let context = try CurrencyConversionContext(
            displayCurrency: .eur,
            currentUSDToDisplayRate: 1,
            historicalUSDToDisplayRatesByDay: [day: #require(Decimal(string: "0.8"))])

        let points = PerformanceFeature.aggregateCategorySnapshots(
            entries: [
                CategorySnapshotEntry(accountId: acct, assetId: asset, timestamp: morning, category: .major, usdValue: 1000),
                CategorySnapshotEntry(accountId: acct, assetId: asset, timestamp: evening, category: .major, usdValue: 1200)
            ],
            conversionContext: context)

        #expect(points.count == 1)
        #expect(points.first?.value == 960)
    }

    @Test func `omits categories with zero on both days`() throws {
        let cal = Calendar.current
        let day1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))

        let acct = UUID()
        let btc = UUID()
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day1, category: .major, usdValue: 1000),
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day2, category: .major, usdValue: 1100)
        ]

        let changes = PerformanceFeature.computeCategoryChanges(entries: entries)

        #expect(changes.count == 1) // only major
    }

    @Test func `empty returns empty`() {
        let changes = PerformanceFeature.computeCategoryChanges(entries: [])
        #expect(changes.isEmpty)
    }

    @Test func `uses only latest snapshot per asset per day not sum of all syncs`() throws {
        // UTC-pinned because PerformanceFeature.deduplicateByDayAndAsset uses UTC day buckets.
        // Without pinning, hours like 8/20 land in different UTC days depending on locale.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let acct = UUID()
        let btc = UUID()

        let day1Morning = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 8)))
        let day1Evening = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 20)))
        let day2Morning = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 8)))
        let day2Evening = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 20)))

        // Two syncs on each day for the same (accountId, assetId)
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day1Morning, category: .major, usdValue: 900),
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day1Evening, category: .major, usdValue: 1000),
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day2Morning, category: .major, usdValue: 1100),
            CategorySnapshotEntry(accountId: acct, assetId: btc, timestamp: day2Evening, category: .major, usdValue: 1200)
        ]

        let changes = PerformanceFeature.computeCategoryChanges(entries: entries)

        let major = changes.first { $0.name == "Major" }
        // Must use the latest snapshot per (day, accountId, assetId), not sum all syncs
        #expect(major?.startValue == 1000) // day1Evening only, not 900 + 1000 = 1900
        #expect(major?.endValue == 1200) // day2Evening only, not 1100 + 1200 = 2300
        #expect(major?.percentChange == Decimal(string: "0.2")!)
    }
}

// MARK: - Data Reducer Tests

// Reducer lifecycle and projection tests for the issue #97 data boundary.

@MainActor
struct PerformanceFeatureDataTests {
    // MARK: - One load per dataRequested

    @Test func `dataRequested triggers exactly one performanceData load`() async {
        let recorder = PerformanceLoadCallRecorder()
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in
                await recorder.record()
                return .empty
            }
        }

        let request = PerformanceDataRequest(
            startDate: Date(timeIntervalSince1970: 1_704_067_200))

        await store.send(.dataRequested(request)) {
            $0.dataRequestGeneration = 1
            $0.activeDataRequestID = "performance-data|1"
            $0.isDataLoading = true
        }
        await store.receive(\.dataResponse) {
            $0.isDataLoading = false
        }

        #expect(
            await recorder.count == 1,
            "Exactly one client.load call must be made per dataRequested")
    }

    @Test func `data failure stops loading and surfaces the error`() async {
        var initial = PerformanceFeature.State()
        initial.activeDataRequestID = "performance-data|1"
        initial.isDataLoading = true
        let store = TestStore(initialState: initial) {
            PerformanceFeature()
        }

        await store.send(.dataResponse(
            "performance-data|1",
            .failure(PerformanceDataClientError(message: "Store unavailable")))) {
                $0.isDataLoading = false
                $0.dataLoadError = "Store unavailable"
            }
    }

    // MARK: - Stale response guard

    /// A response for a superseded generation must be silently dropped:
    /// the guard `state.activeDataRequestID == requestID` rejects it, leaving
    /// isDataLoading true and every other field unchanged.
    @Test func `stale response for a prior generation is silently dropped`() async {
        // Pre-seed: generation 2 is the active request; generation 1 has been superseded.
        var initial = PerformanceFeature.State()
        initial.dataRequestGeneration = 2
        initial.activeDataRequestID = "performance-data|2"
        initial.isDataLoading = true

        let store = TestStore(initialState: initial) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in .empty }
        }

        // Delivering a gen-1 response: guard fails because "performance-data|2" ≠ "performance-data|1".
        await store.send(.dataResponse("performance-data|1", .success(.empty)))
        // No mutation block → TestStore verifies no state change occurred.
        // isDataLoading remains true; activeDataRequestID remains "performance-data|2".
    }

    // MARK: - screenExited rejects late response

    /// After screenExited clears activeDataRequestID to nil, any late dataResponse
    /// is rejected by the same guard (nil ≠ any non-nil requestID).
    @Test func `response arriving after screenExited is dropped`() async {
        var initial = PerformanceFeature.State()
        initial.dataRequestGeneration = 1
        initial.activeDataRequestID = "performance-data|1"
        initial.isDataLoading = true

        let store = TestStore(initialState: initial) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in .empty }
        }

        await store.send(.screenExited) {
            $0.activeDataRequestID = nil
            $0.isDataLoading = false
        }

        // Late response: activeDataRequestID is nil → nil == "performance-data|1" is false → dropped.
        await store.send(.dataResponse("performance-data|1", .success(.empty)))
        // No mutation block → state remains at post-exit values.
    }

    // MARK: - dataInvalidated

    /// dataInvalidated must only increment dataRevision; no client load is triggered
    /// (the reload comes from PerformanceView's .task(id:) detecting the revision change).
    @Test func `dataInvalidated increments dataRevision and triggers no client load`() async {
        let recorder = PerformanceLoadCallRecorder()
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in
                await recorder.record()
                return .empty
            }
        }

        await store.send(.dataInvalidated) {
            $0.dataRevision = 1
        }

        #expect(
            await recorder.isEmpty,
            "dataInvalidated bumps dataRevision only; reload is driven by the view's task-ID change, not by a reducer effect")
    }

    // MARK: - Category toggle reprojects without loading

    /// portfolioCategoryToggled must update the in-state indexed cache and return .none —
    /// it must never call performanceData.load or aggregate all snapshot rows again.
    @Test func `portfolioCategoryToggled updates cache without calling performanceData load`() async throws {
        let recorder = PerformanceLoadCallRecorder()
        let day = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
        let account = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let assetId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let catA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let catB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let entries = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetId,
                timestamp: day.addingTimeInterval(8 * 3600),
                category: .other,
                categoryID: catA,
                categoryName: "Category A",
                usdValue: 1000),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetId,
                timestamp: day.addingTimeInterval(20 * 3600),
                category: .other,
                categoryID: catB,
                categoryName: "Category B",
                usdValue: 1200)
        ]
        let categoryChart = PerformanceCategoryChartCache(entries: entries)

        var initial = PerformanceFeature.State()
        initial.categoryChart = categoryChart
        initial.assetChartPoints = categoryChart.points

        let store = TestStore(initialState: initial) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in
                await recorder.record()
                return .empty
            }
        }

        var expectedCategoryChart = categoryChart
        expectedCategoryChart.setDisabledCategoryIDs([catB])

        await store.send(.portfolioCategoryToggled(catB)) {
            $0.disabledPortfolioCategoryIDs = [catB]
            $0.categoryChart = expectedCategoryChart
            $0.assetChartPoints = expectedCategoryChart.points
        }

        #expect(
            await recorder.isEmpty,
            "A category toggle must update the cache; it must never call performanceData.load")
    }
}

// MARK: - Load call recorder (shared by PerformanceFeatureDataTests)

private actor PerformanceLoadCallRecorder {
    private(set) var count = 0
    private(set) var isEmpty = true

    func record() {
        count += 1
        isEmpty = false
    }
}

// MARK: - Category Chart Cache Parity Tests

// Asserts that PerformanceCategoryChartCache produces a result byte-for-byte identical to
// the independent legacy oracle for resolver-shaped inputs, where each category ID has one
// canonical name. Conflicting-name sequence stability is covered separately below.
//
// Independence is preserved because the oracle never touches the indexed cache path.
//
// Tie-break contract: for equal timestamps within a (utcDay, account, asset) group,
// the entry appearing earlier in the input array wins — identical to legacy dedup's
// `existing.timestamp >= entry.timestamp { continue }`. Build fixtures as ordered arrays.

struct PerformanceCategoryChartParityTests {
    // MARK: - Helpers

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour))!
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// Core parity oracle: both pipelines must return identical [CategoryChartPoint] arrays
    /// (same values, same sort order) for every disabled-category set.
    private func assertParity(
        entries: [CategorySnapshotEntry],
        disabledCategoryIDs: Set<String>,
        sourceContext: String = #function) {
        var cache = PerformanceCategoryChartCache(entries: entries)
        cache.setDisabledCategoryIDs(disabledCategoryIDs)
        let newPoints = cache.points
        let enabledEntries = entries.filter { !disabledCategoryIDs.contains($0.categoryID) }
        let legacyPoints = PerformanceFeature.aggregateCategorySnapshots(entries: enabledEntries)

        // Both functions use the same sort comparator (date asc, categoryName, categoryID).
        #expect(
            newPoints == legacyPoints,
            "Indexed cache must be byte-for-byte equal to legacy filter-then-aggregate (\(sourceContext), disabled: \(disabledCategoryIDs))")
    }

    // MARK: - Round-trip: no disabled categories

    /// Baseline: with no disabled categories and simple multi-day multi-asset data
    /// the indexed cache must exactly match the legacy pipeline.
    @Test func `no disabled categories produce cache points identical to legacy`() {
        let account = uuid(1)
        let assetA = uuid(10)
        let assetB = uuid(11)
        let catA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let catB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let d1 = utcDate(2024, 1, 1, hour: 12)
        let d2 = utcDate(2024, 1, 2, hour: 12)

        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetA,
                timestamp: d1,
                category: .major,
                categoryID: catA,
                categoryName: "Alpha",
                usdValue: 1000),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetA,
                timestamp: d2,
                category: .major,
                categoryID: catA,
                categoryName: "Alpha",
                usdValue: 1100),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetB,
                timestamp: d1,
                category: .stablecoin,
                categoryID: catB,
                categoryName: "Beta",
                usdValue: 500),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetB,
                timestamp: d2,
                category: .stablecoin,
                categoryID: catB,
                categoryName: "Beta",
                usdValue: 500)
        ]

        assertParity(entries: entries, disabledCategoryIDs: [])
    }

    // MARK: - Mid-day category change

    /// An asset that switches category mid-day produces two candidates in its source group.
    /// Both pipelines must agree regardless of which category is disabled:
    ///   - neither disabled: both pick the evening (later) category
    ///   - evening disabled: both promote the morning (earlier) category
    ///   - morning disabled: both keep the evening category
    @Test func `mid-day category change matches legacy filter-then-aggregate`() {
        let account = uuid(1)
        let assetX = uuid(10)
        let catA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let catB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let morning = utcDate(2024, 1, 1, hour: 8)
        let evening = utcDate(2024, 1, 1, hour: 20)

        // catA in the morning, catB in the evening — mid-day category change.
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetX,
                timestamp: morning,
                category: .other,
                categoryID: catA,
                categoryName: "Alpha",
                usdValue: 1000),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetX,
                timestamp: evening,
                category: .other,
                categoryID: catB,
                categoryName: "Beta",
                usdValue: 1200)
        ]

        // All enabled: both pipelines pick catB (evening, later timestamp).
        assertParity(entries: entries, disabledCategoryIDs: [])

        // catB disabled: both pipelines promote catA (earlier, now the only enabled candidate).
        assertParity(entries: entries, disabledCategoryIDs: [catB])

        // catA disabled: both pipelines keep catB (later timestamp, unaffected by disabling catA).
        assertParity(entries: entries, disabledCategoryIDs: [catA])
    }

    // MARK: - Disabled latest (same category, two syncs)

    /// Two sync rows for the same (day, account, asset, category): source group retains only
    /// the latest one per category. Disabling that category must empty both pipelines.
    @Test func `disabling the only remaining category produces empty output in both pipelines`() {
        let account = uuid(1)
        let assetY = uuid(11)
        let catC = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        let t1 = utcDate(2024, 1, 1, hour: 8)
        let t2 = utcDate(2024, 1, 1, hour: 20)

        // Two syncs, same category; source group retains only t2 (latest per categoryID).
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetY,
                timestamp: t1,
                category: .other,
                categoryID: catC,
                categoryName: "Gamma",
                usdValue: 500),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetY,
                timestamp: t2,
                category: .other,
                categoryID: catC,
                categoryName: "Gamma",
                usdValue: 600)
        ]

        // All enabled: both use t2's value (600).
        assertParity(entries: entries, disabledCategoryIDs: [])

        // catC disabled: both pipelines produce [].
        assertParity(entries: entries, disabledCategoryIDs: [catC])
    }

    // MARK: - Equal timestamps

    /// When two candidates for the same (day, account, asset) have equal timestamps but
    /// different categories, the earlier-in-array entry wins in both pipelines.
    /// Testing with one category disabled removes the tie-break ambiguity and proves that
    /// both pipelines agree on the surviving entry.
    @Test func `equal-timestamp candidates satisfy legacy first-encountered tie-break in both pipelines`() {
        let account = uuid(1)
        let assetZ = uuid(12)
        let catD = "dddddddd-dddd-dddd-dddd-dddddddddddd"
        let catE = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        let noon = utcDate(2024, 1, 1, hour: 12)

        // catD appears first in the array; catE appears second — both at the same timestamp.
        // "first-encountered wins on equal timestamp" means catD wins when both are enabled.
        let entries: [CategorySnapshotEntry] = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetZ,
                timestamp: noon,
                category: .other,
                categoryID: catD,
                categoryName: "Delta",
                usdValue: 400),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetZ,
                timestamp: noon,
                category: .other,
                categoryID: catE,
                categoryName: "Epsilon",
                usdValue: 500)
        ]

        // catD disabled: both pipelines produce catE (only remaining candidate).
        assertParity(entries: entries, disabledCategoryIDs: [catD])

        // catE disabled: both pipelines produce catD (only remaining candidate).
        assertParity(entries: entries, disabledCategoryIDs: [catE])

        // All enabled: both pipelines apply the same first-encountered tie-break → same winner (catD).
        assertParity(entries: entries, disabledCategoryIDs: [])
    }

    @Test func `incremental disable and enable transitions preserve zero-valued points`() {
        let account = uuid(1)
        let assetA = uuid(20)
        let assetB = uuid(21)
        let catA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let catB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let morning = utcDate(2024, 1, 1, hour: 8)
        let noon = utcDate(2024, 1, 1, hour: 12)
        let evening = utcDate(2024, 1, 1, hour: 20)
        let entries = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetA,
                timestamp: morning,
                category: .other,
                categoryID: catA,
                categoryName: "Alpha",
                usdValue: 100),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetA,
                timestamp: evening,
                category: .other,
                categoryID: catB,
                categoryName: "Beta",
                usdValue: 200),
            CategorySnapshotEntry(
                accountId: account,
                assetId: assetB,
                timestamp: noon,
                category: .other,
                categoryID: catA,
                categoryName: "Alpha",
                usdValue: -100)
        ]
        var cache = PerformanceCategoryChartCache(entries: entries)

        #expect(cache.points.first { $0.categoryID == catA }?.value == -100)
        #expect(cache.points.first { $0.categoryID == catB }?.value == 200)

        cache.setDisabledCategoryIDs([catB])
        #expect(cache.points.count == 1)
        #expect(cache.points.first?.categoryID == catA)
        #expect(cache.points.first?.value == 0)

        cache.setDisabledCategoryIDs([catA, catB])
        #expect(cache.points.isEmpty)

        cache.setDisabledCategoryIDs([catA])
        #expect(cache.points.count == 1)
        #expect(cache.points.first?.categoryID == catB)
        #expect(cache.points.first?.value == 200)

        cache.setDisabledCategoryIDs([])
        #expect(cache.points.first { $0.categoryID == catA }?.value == -100)
        #expect(cache.points.first { $0.categoryID == catB }?.value == 200)
    }

    @Test func `incremental transitions equal fresh cache when category labels conflict`() {
        let account = uuid(1)
        let catA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let catB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let entries = [
            CategorySnapshotEntry(
                accountId: account,
                assetId: uuid(30),
                timestamp: utcDate(2024, 1, 1, hour: 10),
                category: .other,
                categoryID: catB,
                categoryName: "Beta",
                usdValue: 2),
            CategorySnapshotEntry(
                accountId: account,
                assetId: uuid(30),
                timestamp: utcDate(2024, 1, 1, hour: 8),
                category: .other,
                categoryID: catA,
                categoryName: "Alpha first",
                usdValue: 1),
            CategorySnapshotEntry(
                accountId: account,
                assetId: uuid(31),
                timestamp: utcDate(2024, 1, 1, hour: 9),
                category: .other,
                categoryID: catA,
                categoryName: "Alpha second",
                usdValue: 1)
        ]
        var cache = PerformanceCategoryChartCache(entries: entries)

        for disabledCategoryIDs: Set<String> in [[catB], [catA, catB], [catA], []] {
            cache.setDisabledCategoryIDs(disabledCategoryIDs)
            let freshCache = PerformanceCategoryChartCache(
                entries: entries,
                disabledCategoryIDs: disabledCategoryIDs)
            #expect(cache.points == freshCache.points)
        }
    }
}
