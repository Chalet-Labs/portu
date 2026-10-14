import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct AssetDetailFeatureTests {
    // MARK: - Chart Mode Selection

    @Test func `chart mode selection updates state`() async {
        let store = TestStore(initialState: AssetDetailFeature.State()) {
            AssetDetailFeature()
        }

        await store.send(.chartModeChanged(.dollarValue)) {
            $0.chartMode = .dollarValue
        }
        await store.send(.chartModeChanged(.amount)) {
            $0.chartMode = .amount
        }
        await store.send(.chartModeChanged(.price)) {
            $0.chartMode = .price
        }
    }

    // MARK: - Time Range Selection

    @Test func `time range selection updates state`() async {
        let store = TestStore(initialState: AssetDetailFeature.State()) {
            AssetDetailFeature()
        }

        await store.send(.timeRangeChanged(.oneWeek)) {
            $0.selectedRange = .oneWeek
        }
        await store.send(.timeRangeChanged(.threeMonths)) {
            $0.selectedRange = .threeMonths
        }
        await store.send(.timeRangeChanged(.oneYear)) {
            $0.selectedRange = .oneYear
        }
        await store.send(.timeRangeChanged(.oneMonth)) {
            $0.selectedRange = .oneMonth
        }
    }
}

// MARK: - Snapshot Aggregation

struct AssetDetailSnapshotTests {
    private let assetId = UUID()
    private let accountId = UUID()
    private let otherAccountId = UUID()
    private let cal = Calendar.current

    @Test func `same account intra day takes latest not sum`() throws {
        let noon = try #require(cal.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12)))
        let day = cal.startOfDay(for: noon)

        let entries = [
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: noon,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0),
            SnapshotEntry(
                accountId: accountId, assetId: assetId,
                timestamp: noon.addingTimeInterval(3600),
                grossUSD: 3000, borrowUSD: 1000, grossAmount: 1, borrowAmount: 0.4)
        ]

        let points = AssetDetailFeature.aggregateSnapshots(entries: entries)

        #expect(points.count == 1)
        #expect(points[0].date == day)
        // Correct: latest entry wins (3000), not sum (8000)
        #expect(points[0].grossUSD == 3000)
        #expect(points[0].borrowUSD == 1000)
        #expect(points[0].grossAmount == 1)
        #expect(points[0].borrowAmount == Decimal(string: "0.4")!)
    }

    @Test func `multiple syncs same day takes latest not sum`() throws {
        let base = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 8)))
        let day = cal.startOfDay(for: base)

        let entries = [
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: base,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0),
            SnapshotEntry(
                accountId: accountId, assetId: assetId,
                timestamp: base.addingTimeInterval(4 * 3600),
                grossUSD: 6000, borrowUSD: 500, grossAmount: 2.5, borrowAmount: 0.2),
            SnapshotEntry(
                accountId: accountId, assetId: assetId,
                timestamp: base.addingTimeInterval(10 * 3600),
                grossUSD: 5500, borrowUSD: 200, grossAmount: 2.2, borrowAmount: 0.1)
        ]

        let points = AssetDetailFeature.aggregateSnapshots(entries: entries)

        #expect(points.count == 1)
        #expect(points[0].date == day)
        // Latest entry (18:00) should win — not sum of all three
        #expect(points[0].grossUSD == 5500)
        #expect(points[0].borrowUSD == 200)
    }

    @Test func `multiple accounts same day sums across accounts`() throws {
        let noon = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12)))
        let day = cal.startOfDay(for: noon)

        let entries = [
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: noon,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0),
            SnapshotEntry(
                accountId: otherAccountId, assetId: assetId, timestamp: noon,
                grossUSD: 3000, borrowUSD: 0, grossAmount: 1, borrowAmount: 0)
        ]

        let points = AssetDetailFeature.aggregateSnapshots(entries: entries)

        #expect(points.count == 1)
        #expect(points[0].date == day)
        // Different accounts on same day: sum is correct
        #expect(points[0].grossUSD == 8000)
        #expect(points[0].grossAmount == 3)
    }

    @Test func `intra day dedup preserves cross day data`() throws {
        let d1Morning = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 9)))
        let d1Evening = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 21)))
        let d2Morning = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 11, hour: 9)))
        let d2Evening = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 11, hour: 21)))

        let entries = [
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: d1Morning,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0),
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: d1Evening,
                grossUSD: 5200, borrowUSD: 0, grossAmount: 2, borrowAmount: 0),
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: d2Morning,
                grossUSD: 4800, borrowUSD: 0, grossAmount: 2, borrowAmount: 0),
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: d2Evening,
                grossUSD: 4900, borrowUSD: 100, grossAmount: 2, borrowAmount: 0.05)
        ]

        let points = AssetDetailFeature.aggregateSnapshots(entries: entries)

        #expect(points.count == 2)
        // Day 1: latest is evening → 5200
        #expect(points[0].grossUSD == 5200)
        // Day 2: latest is evening → 4900
        #expect(points[1].grossUSD == 4900)
        #expect(points[1].borrowUSD == 100)
    }

    @Test func `sorted by date ascending`() throws {
        let day1 = try #require(cal.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12)))

        let entries = [
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: day2,
                grossUSD: 3000, borrowUSD: 0, grossAmount: 1, borrowAmount: 0),
            SnapshotEntry(
                accountId: accountId, assetId: assetId, timestamp: day1,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0)
        ]

        let points = AssetDetailFeature.aggregateSnapshots(entries: entries)

        #expect(points.count == 2)
        #expect(points[0].date < points[1].date)
    }

    @Test func `empty input returns empty`() {
        let points = AssetDetailFeature.aggregateSnapshots(entries: [])
        #expect(points.isEmpty)
    }
}

// MARK: - Category Chart Aggregation

struct AssetsChartAggregationTests {
    private let accountA = UUID()
    private let assetBTC = UUID()
    private let assetETH = UUID()
    /// PerformanceFeature.aggregateCategorySnapshots now buckets by UTC day to align
    /// with the historical-price cache, so tests must also pin to UTC.
    private let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func `category chart dedup takes latest per day`() throws {
        let morning = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 9)))
        let evening = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 21)))
        let day = cal.startOfDay(for: morning)

        let entries = [
            CategorySnapshotEntry(
                accountId: accountA, assetId: assetBTC, timestamp: morning,
                category: .major, usdValue: 5000),
            CategorySnapshotEntry(
                accountId: accountA, assetId: assetBTC, timestamp: evening,
                category: .major, usdValue: 5500)
        ]

        let points = PerformanceFeature.aggregateCategorySnapshots(entries: entries)

        #expect(points.count == 1)
        #expect(points[0].date == day)
        // Latest entry should win — not sum
        #expect(points[0].value == 5500)
    }

    @Test func `category chart sums across categories same day`() throws {
        let noon = try #require(cal.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12)))

        let entries = [
            CategorySnapshotEntry(
                accountId: accountA, assetId: assetBTC, timestamp: noon,
                category: .major, usdValue: 5000),
            CategorySnapshotEntry(
                accountId: accountA, assetId: assetETH, timestamp: noon,
                category: .defi, usdValue: 2000)
        ]

        let points = PerformanceFeature.aggregateCategorySnapshots(entries: entries)

        let major = points.first(where: { $0.categoryName == "Major" })
        let defi = points.first(where: { $0.categoryName == "Defi" })
        #expect(major?.value == 5000)
        #expect(defi?.value == 2000)
    }
}
