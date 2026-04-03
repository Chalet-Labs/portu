import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct AssetDetailFeatureTests {
    // MARK: - B1: Chart Mode Selection

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

    // MARK: - B2: Time Range Selection

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

// MARK: - B3: Position Row Aggregation

struct AssetDetailPositionRowTests {
    @Test func `uses live price for usd balance`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Wallet A", protocolName: nil,
            positionType: .idle, chain: .ethereum, role: .balance,
            amount: 10, usdValue: 25000, coinGeckoId: "ethereum")

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: ["ethereum": 3000])

        #expect(rows.count == 1)
        #expect(rows[0].amount == 10)
        #expect(rows[0].usdBalance == 30000) // 10 * 3000
    }

    @Test func `falls back to sync-time usd value`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Kraken", protocolName: nil,
            positionType: .idle, chain: nil, role: .balance,
            amount: 100, usdValue: 500, coinGeckoId: nil)

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:])

        #expect(rows.count == 1)
        #expect(rows[0].usdBalance == 500)
    }

    @Test func `populates account name, platform, context, network`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "DeFi Wallet", protocolName: "Aave V3",
            positionType: .lending, chain: .arbitrum, role: .supply,
            amount: 5, usdValue: 15000, coinGeckoId: nil)

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:])

        #expect(rows[0].accountName == "DeFi Wallet")
        #expect(rows[0].platformName == "Aave V3")
        #expect(rows[0].context == "Lending")
        #expect(rows[0].network == "Arbitrum")
    }

    @Test func `nil protocol defaults to Wallet`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Main", protocolName: nil,
            positionType: .idle, chain: .ethereum, role: .balance,
            amount: 1, usdValue: 3000, coinGeckoId: nil)

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:])

        #expect(rows[0].platformName == "Wallet")
    }

    @Test func `nil chain defaults to Off-chain`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Coinbase", protocolName: nil,
            positionType: .idle, chain: nil, role: .balance,
            amount: 1, usdValue: 60000, coinGeckoId: nil)

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:])

        #expect(rows[0].network == "Off-chain")
    }

    @Test func `sorted by usd balance descending`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Small", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 1, usdValue: 100, coinGeckoId: nil),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Large", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 10, usdValue: 1000, coinGeckoId: nil)
        ]

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: entries, prices: [:])

        #expect(rows[0].accountName == "Large")
        #expect(rows[1].accountName == "Small")
    }
}

// MARK: - B4: Holdings Summary

struct AssetDetailHoldingsSummaryTests {
    @Test func `total amount sums positive minus borrow`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .supply,
                amount: 10, usdValue: 30000, coinGeckoId: "ethereum"),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "B", protocolName: "Aave",
                positionType: .lending, chain: .ethereum, role: .borrow,
                amount: 3, usdValue: 9000, coinGeckoId: "ethereum")
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: ["ethereum": 3000])

        #expect(summary.totalAmount == 7) // 10 - 3
    }

    @Test func `total value uses live price when available`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 5, usdValue: 10000, coinGeckoId: "ethereum")
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: ["ethereum": 3000])

        #expect(summary.totalValue == 15000) // 5 * 3000
    }

    @Test func `total value falls back to sum of usd values`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: nil, role: .balance,
                amount: 100, usdValue: 500, coinGeckoId: nil),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "B", protocolName: nil,
                positionType: .idle, chain: nil, role: .supply,
                amount: 50, usdValue: 250, coinGeckoId: nil)
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:])

        #expect(summary.totalValue == 750) // 500 + 250
    }

    @Test func `account count counts distinct accounts`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Wallet A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 5, usdValue: 15000, coinGeckoId: nil),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Wallet A", protocolName: "Aave",
                positionType: .lending, chain: .ethereum, role: .supply,
                amount: 3, usdValue: 9000, coinGeckoId: nil),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Coinbase", protocolName: nil,
                positionType: .idle, chain: nil, role: .balance,
                amount: 2, usdValue: 6000, coinGeckoId: nil)
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:])

        #expect(summary.accountCount == 2) // "Wallet A" and "Coinbase"
    }

    @Test func `by chain groups positive tokens with share and value`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 8, usdValue: 24000, coinGeckoId: nil),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "B", protocolName: nil,
                positionType: .idle, chain: .arbitrum, role: .balance,
                amount: 2, usdValue: 6000, coinGeckoId: nil)
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:])

        #expect(summary.byChain.count == 2)
        // Sorted by value desc → Ethereum first
        #expect(summary.byChain[0].name == "Ethereum")
        #expect(summary.byChain[0].share == Decimal(8) / Decimal(10)) // 80%
        #expect(summary.byChain[0].value == 24000)
        #expect(summary.byChain[1].name == "Arbitrum")
    }

    @Test func `by chain excludes borrow tokens`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .supply,
                amount: 10, usdValue: 30000, coinGeckoId: nil),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: "Aave",
                positionType: .lending, chain: .ethereum, role: .borrow,
                amount: 3, usdValue: 9000, coinGeckoId: nil)
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:])

        // Only supply token counts in byChain
        #expect(summary.byChain.count == 1)
        #expect(summary.byChain[0].share == 1) // 100% since only one chain with positive
    }
}

// MARK: - B5: Snapshot Aggregation

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

// MARK: - B5b: Category Chart Aggregation

struct AssetsChartAggregationTests {
    private let accountA = UUID()
    private let accountB = UUID()
    private let assetBTC = UUID()
    private let assetETH = UUID()
    private let cal = Calendar.current

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

        let major = points.first { $0.category == "Major" }
        let defi = points.first { $0.category == "Defi" }
        #expect(major?.value == 5000)
        #expect(defi?.value == 2000)
    }
}

// MARK: - B6: Header Price Display

struct AssetDetailHeaderPriceTests {
    @Test func `returns price and change when available`() throws {
        let info = try AssetDetailFeature.headerPriceInfo(
            coinGeckoId: "bitcoin",
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": #require(Decimal(string: "0.035"))])

        let result = try #require(info)
        #expect(result.price == 65000)
        #expect(result.change24h == Decimal(string: "0.035")!)
    }

    @Test func `returns price without change when change unavailable`() throws {
        let info = AssetDetailFeature.headerPriceInfo(
            coinGeckoId: "bitcoin",
            prices: ["bitcoin": 65000],
            changes24h: [:])

        let result = try #require(info)
        #expect(result.price == 65000)
        #expect(result.change24h == nil)
    }

    @Test func `returns nil when no coinGeckoId`() throws {
        let info = try AssetDetailFeature.headerPriceInfo(
            coinGeckoId: nil,
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": #require(Decimal(string: "0.035"))])

        #expect(info == nil)
    }

    @Test func `returns nil when no live price`() {
        let info = AssetDetailFeature.headerPriceInfo(
            coinGeckoId: "bitcoin",
            prices: [:],
            changes24h: [:])

        #expect(info == nil)
    }
}
