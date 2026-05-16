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
        await store.send(.chartModeChanged(.pnl)) {
            $0.chartMode = .pnl
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

// MARK: - PnL Bar Computation

struct PerformancePnLTests {
    @Test func `computes daily and cumulative pnl`() throws {
        let cal = Calendar.current
        let d1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))
        let d2 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 12)))
        let d3 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 12)))

        let daily: [(Date, Decimal)] = [(d1, 1000), (d2, 1100), (d3, 1050)]

        let bars = PerformanceFeature.computePnLBars(from: daily)

        #expect(bars.count == 2) // first day is baseline
        #expect(bars[0].pnl == 100) // 1100 - 1000
        #expect(bars[0].cumulative == 100)
        #expect(bars[1].pnl == -50) // 1050 - 1100
        #expect(bars[1].cumulative == 50) // 100 + (-50)
    }

    @Test func `fewer than 2 days returns empty`() throws {
        let cal = Calendar.current
        let d1 = try #require(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))

        let bars = PerformanceFeature.computePnLBars(from: [(d1, 1000)])

        #expect(bars.isEmpty)
    }

    @Test func `empty returns empty`() {
        let bars = PerformanceFeature.computePnLBars(from: [])
        #expect(bars.isEmpty)
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
        let cal = Calendar.current
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
