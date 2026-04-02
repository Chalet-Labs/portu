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
            amount: 10, usdValue: 25000, coinGeckoId: "ethereum"
        )

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: ["ethereum": 3000]
        )

        #expect(rows.count == 1)
        #expect(rows[0].amount == 10)
        #expect(rows[0].usdBalance == 30000) // 10 * 3000
    }

    @Test func `falls back to sync-time usd value`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Kraken", protocolName: nil,
            positionType: .idle, chain: nil, role: .balance,
            amount: 100, usdValue: 500, coinGeckoId: nil
        )

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].usdBalance == 500)
    }

    @Test func `populates account name, platform, context, network`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "DeFi Wallet", protocolName: "Aave V3",
            positionType: .lending, chain: .arbitrum, role: .supply,
            amount: 5, usdValue: 15000, coinGeckoId: nil
        )

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:]
        )

        #expect(rows[0].accountName == "DeFi Wallet")
        #expect(rows[0].platformName == "Aave V3")
        #expect(rows[0].context == "Lending")
        #expect(rows[0].network == "Arbitrum")
    }

    @Test func `nil protocol defaults to Wallet`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Main", protocolName: nil,
            positionType: .idle, chain: .ethereum, role: .balance,
            amount: 1, usdValue: 3000, coinGeckoId: nil
        )

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:]
        )

        #expect(rows[0].platformName == "Wallet")
    }

    @Test func `nil chain defaults to Off-chain`() {
        let entry = PositionTokenEntry(
            tokenId: UUID(), accountName: "Coinbase", protocolName: nil,
            positionType: .idle, chain: nil, role: .balance,
            amount: 1, usdValue: 60000, coinGeckoId: nil
        )

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: [entry], prices: [:]
        )

        #expect(rows[0].network == "Off-chain")
    }

    @Test func `sorted by usd balance descending`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Small", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 1, usdValue: 100, coinGeckoId: nil
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Large", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 10, usdValue: 1000, coinGeckoId: nil
            )
        ]

        let rows = AssetDetailFeature.aggregatePositionRows(
            tokens: entries, prices: [:]
        )

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
                amount: 10, usdValue: 30000, coinGeckoId: "ethereum"
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "B", protocolName: "Aave",
                positionType: .lending, chain: .ethereum, role: .borrow,
                amount: 3, usdValue: 9000, coinGeckoId: "ethereum"
            )
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: ["ethereum": 3000]
        )

        #expect(summary.totalAmount == 7) // 10 - 3
    }

    @Test func `total value uses live price when available`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 5, usdValue: 10000, coinGeckoId: "ethereum"
            )
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: ["ethereum": 3000]
        )

        #expect(summary.totalValue == 15000) // 5 * 3000
    }

    @Test func `total value falls back to sum of usd values`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: nil, role: .balance,
                amount: 100, usdValue: 500, coinGeckoId: nil
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "B", protocolName: nil,
                positionType: .idle, chain: nil, role: .supply,
                amount: 50, usdValue: 250, coinGeckoId: nil
            )
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:]
        )

        #expect(summary.totalValue == 750) // 500 + 250
    }

    @Test func `account count counts distinct accounts`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Wallet A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 5, usdValue: 15000, coinGeckoId: nil
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Wallet A", protocolName: "Aave",
                positionType: .lending, chain: .ethereum, role: .supply,
                amount: 3, usdValue: 9000, coinGeckoId: nil
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "Coinbase", protocolName: nil,
                positionType: .idle, chain: nil, role: .balance,
                amount: 2, usdValue: 6000, coinGeckoId: nil
            )
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:]
        )

        #expect(summary.accountCount == 2) // "Wallet A" and "Coinbase"
    }

    @Test func `by chain groups positive tokens with share and value`() {
        let entries = [
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: nil,
                positionType: .idle, chain: .ethereum, role: .balance,
                amount: 8, usdValue: 24000, coinGeckoId: nil
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "B", protocolName: nil,
                positionType: .idle, chain: .arbitrum, role: .balance,
                amount: 2, usdValue: 6000, coinGeckoId: nil
            )
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:]
        )

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
                amount: 10, usdValue: 30000, coinGeckoId: nil
            ),
            PositionTokenEntry(
                tokenId: UUID(), accountName: "A", protocolName: "Aave",
                positionType: .lending, chain: .ethereum, role: .borrow,
                amount: 3, usdValue: 9000, coinGeckoId: nil
            )
        ]

        let summary = AssetDetailFeature.computeHoldingsSummary(
            tokens: entries, prices: [:]
        )

        // Only supply token counts in byChain
        #expect(summary.byChain.count == 1)
        #expect(summary.byChain[0].share == 1) // 100% since only one chain with positive
    }
}

// MARK: - B5: Snapshot Aggregation

struct AssetDetailSnapshotTests {
    private let assetId = UUID()
    private let otherAssetId = UUID()
    private let cal = Calendar.current

    @Test func `aggregates by day across accounts`() throws {
        // Use midday to avoid timezone-boundary issues
        let noon = try #require(cal.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12)))
        let day = cal.startOfDay(for: noon)

        let entries = [
            SnapshotEntry(
                assetId: assetId, timestamp: noon,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0
            ),
            SnapshotEntry(
                assetId: assetId, timestamp: noon.addingTimeInterval(3600), // same day
                grossUSD: 3000, borrowUSD: 1000, grossAmount: 1, borrowAmount: 0.4
            )
        ]

        let points = AssetDetailFeature.aggregateSnapshots(entries: entries)

        #expect(points.count == 1)
        #expect(points[0].date == day)
        #expect(points[0].grossUSD == 8000)
        #expect(points[0].borrowUSD == 1000)
        #expect(points[0].grossAmount == 3)
        #expect(points[0].borrowAmount == Decimal(string: "0.4")!)
    }

    @Test func `sorted by date ascending`() throws {
        let day1 = try #require(cal.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12)))
        let day2 = try #require(cal.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12)))

        let entries = [
            SnapshotEntry(
                assetId: assetId, timestamp: day2,
                grossUSD: 3000, borrowUSD: 0, grossAmount: 1, borrowAmount: 0
            ),
            SnapshotEntry(
                assetId: assetId, timestamp: day1,
                grossUSD: 5000, borrowUSD: 0, grossAmount: 2, borrowAmount: 0
            )
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

// MARK: - B6: Header Price Display

struct AssetDetailHeaderPriceTests {
    @Test func `returns price and change when available`() throws {
        let info = try AssetDetailFeature.headerPriceInfo(
            coinGeckoId: "bitcoin",
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": #require(Decimal(string: "0.035"))]
        )

        let result = try #require(info)
        #expect(result.price == 65000)
        #expect(result.change24h == Decimal(string: "0.035")!)
    }

    @Test func `returns price without change when change unavailable`() throws {
        let info = AssetDetailFeature.headerPriceInfo(
            coinGeckoId: "bitcoin",
            prices: ["bitcoin": 65000],
            changes24h: [:]
        )

        let result = try #require(info)
        #expect(result.price == 65000)
        #expect(result.change24h == nil)
    }

    @Test func `returns nil when no coinGeckoId`() throws {
        let info = try AssetDetailFeature.headerPriceInfo(
            coinGeckoId: nil,
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": #require(Decimal(string: "0.035"))]
        )

        #expect(info == nil)
    }

    @Test func `returns nil when no live price`() {
        let info = AssetDetailFeature.headerPriceInfo(
            coinGeckoId: "bitcoin",
            prices: [:],
            changes24h: [:]
        )

        #expect(info == nil)
    }
}
