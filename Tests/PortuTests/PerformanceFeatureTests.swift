import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct PerformanceFeatureTests {
    // MARK: - B1: Account Filter

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

    // MARK: - B2: Time Range

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

    // MARK: - B3: Chart Mode

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

    // MARK: - B4: Category Toggle

    @Test func `category toggle adds and removes`() async {
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        }

        await store.send(.categoryToggled(.stablecoin)) {
            $0.disabledCategories = [.stablecoin]
        }
        await store.send(.categoryToggled(.major)) {
            $0.disabledCategories = [.stablecoin, .major]
        }
        await store.send(.categoryToggled(.stablecoin)) {
            $0.disabledCategories = [.major]
        }
    }

    // MARK: - B5: Cumulative Toggle

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

// MARK: - B6: Last Per Day

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

// MARK: - B7: PnL Bar Computation

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

// MARK: - B8: Category Change Breakdown

struct PerformanceCategoryChangeTests {
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
}
