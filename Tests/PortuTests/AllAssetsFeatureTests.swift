import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct AllAssetsFeatureTests {
    // MARK: - B1: Tab Selection

    @Test func `tab selection updates state`() async {
        let store = TestStore(initialState: AllAssetsFeature.State()) {
            AllAssetsFeature()
        }

        await store.send(.tabSelected(.platforms)) {
            $0.selectedTab = .platforms
        }
        await store.send(.tabSelected(.networks)) {
            $0.selectedTab = .networks
        }
        await store.send(.tabSelected(.assets)) {
            $0.selectedTab = .assets
        }
    }

    // MARK: - B2: Search Text

    @Test func `search text updates state`() async {
        let store = TestStore(initialState: AllAssetsFeature.State()) {
            AllAssetsFeature()
        }

        await store.send(.searchTextChanged("btc")) {
            $0.searchText = "btc"
        }
        await store.send(.searchTextChanged("")) {
            $0.searchText = ""
        }
    }

    // MARK: - B3: Grouping Change

    @Test func `grouping change updates state`() async {
        let store = TestStore(initialState: AllAssetsFeature.State()) {
            AllAssetsFeature()
        }

        await store.send(.groupingChanged(.category)) {
            $0.grouping = .category
        }
        await store.send(.groupingChanged(.priceSource)) {
            $0.grouping = .priceSource
        }
        await store.send(.groupingChanged(.none)) {
            $0.grouping = .none
        }
    }
}

// MARK: - Pure Function Tests

struct AssetRowAggregationTests {
    // MARK: - B4: Row Aggregation

    @Test func `groups tokens by asset`() {
        let assetId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: assetId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 1,
                usdValue: 60000),
            TokenEntry(
                assetId: assetId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 0.5,
                usdValue: 30000)
        ]

        let rows = AllAssetsFeature.aggregateRows(tokens: tokens, prices: [:])

        #expect(rows.count == 1)
        #expect(rows[0].symbol == "BTC")
        #expect(rows[0].netAmount == 1.5)
    }

    @Test func `uses live prices when available`() {
        let assetId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: assetId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 2,
                usdValue: 120_000)
        ]

        let rows = AllAssetsFeature.aggregateRows(tokens: tokens, prices: ["bitcoin": 65000])

        #expect(rows.count == 1)
        #expect(rows[0].price == 65000)
        #expect(rows[0].value == 130_000) // 2 * 65000
        #expect(rows[0].hasLivePrice == true)
    }

    @Test func `falls back to sync-time price`() {
        let assetId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: assetId,
                symbol: "SHIB",
                name: "Shiba Inu",
                category: .meme,
                coinGeckoId: nil,
                role: .balance,
                amount: 1_000_000,
                usdValue: 50)
        ]

        let rows = AllAssetsFeature.aggregateRows(tokens: tokens, prices: [:])

        #expect(rows.count == 1)
        #expect(rows[0].hasLivePrice == false)
        // Fallback price = positiveUSD / positiveAmount = 50 / 1_000_000
        #expect(rows[0].price == Decimal(50) / Decimal(1_000_000))
        #expect(rows[0].value == 50) // positiveUSD - borrowUSD
    }

    @Test func `computes net amount with borrows`() {
        let assetId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: assetId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: "ethereum",
                role: .supply,
                amount: 10,
                usdValue: 30000),
            TokenEntry(
                assetId: assetId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: "ethereum",
                role: .borrow,
                amount: 3,
                usdValue: 9000)
        ]

        let rows = AllAssetsFeature.aggregateRows(tokens: tokens, prices: ["ethereum": 3000])

        #expect(rows.count == 1)
        #expect(rows[0].netAmount == 7) // 10 - 3
        #expect(rows[0].value == 21000) // 7 * 3000
    }

    @Test func `excludes rewards from aggregation`() {
        let assetId = UUID()
        let rewardAssetId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: assetId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: "ethereum",
                role: .stake,
                amount: 32,
                usdValue: 96000),
            TokenEntry(
                assetId: rewardAssetId,
                symbol: "RPL",
                name: "Rocket Pool",
                category: .defi,
                coinGeckoId: "rocket-pool",
                role: .reward,
                amount: 5,
                usdValue: 150)
        ]

        let rows = AllAssetsFeature.aggregateRows(tokens: tokens, prices: [:])

        #expect(rows.count == 1)
        #expect(rows[0].symbol == "ETH")
    }

    @Test func `handles multiple assets separately`() {
        let btcId = UUID()
        let ethId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: btcId,
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                coinGeckoId: "bitcoin",
                role: .balance,
                amount: 1,
                usdValue: 60000),
            TokenEntry(
                assetId: ethId,
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                coinGeckoId: "ethereum",
                role: .balance,
                amount: 10,
                usdValue: 30000)
        ]

        let rows = AllAssetsFeature.aggregateRows(tokens: tokens, prices: [:])

        #expect(rows.count == 2)
        let symbols = Set(rows.map(\.symbol))
        #expect(symbols == ["BTC", "ETH"])
    }

    // MARK: - B5: Search Filtering

    @Test func `filter matches symbol case-insensitively`() {
        let rows = [
            AssetRowData(
                id: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                netAmount: 1,
                price: 60000,
                value: 60000,
                hasLivePrice: true),
            AssetRowData(
                id: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                netAmount: 10,
                price: 3000,
                value: 30000,
                hasLivePrice: true)
        ]

        let filtered = AllAssetsFeature.filterRows(rows, searchText: "btc")

        #expect(filtered.count == 1)
        #expect(filtered[0].symbol == "BTC")
    }

    @Test func `filter matches name case-insensitively`() {
        let rows = [
            AssetRowData(
                id: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                netAmount: 1,
                price: 60000,
                value: 60000,
                hasLivePrice: true),
            AssetRowData(
                id: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                netAmount: 10,
                price: 3000,
                value: 30000,
                hasLivePrice: true)
        ]

        let filtered = AllAssetsFeature.filterRows(rows, searchText: "ether")

        #expect(filtered.count == 1)
        #expect(filtered[0].symbol == "ETH")
    }

    @Test func `empty search returns all rows`() {
        let rows = [
            AssetRowData(
                id: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                netAmount: 1,
                price: 60000,
                value: 60000,
                hasLivePrice: true),
            AssetRowData(
                id: UUID(),
                symbol: "ETH",
                name: "Ethereum",
                category: .major,
                netAmount: 10,
                price: 3000,
                value: 30000,
                hasLivePrice: true)
        ]

        let filtered = AllAssetsFeature.filterRows(rows, searchText: "")

        #expect(filtered.count == 2)
    }

    // MARK: - B6: CSV Generation

    @Test func `CSV has header and formatted rows`() {
        let rows = [
            AssetRowData(
                id: UUID(),
                symbol: "BTC",
                name: "Bitcoin",
                category: .major,
                netAmount: 1.5,
                price: 60000,
                value: 90000,
                hasLivePrice: true)
        ]

        let csv = AllAssetsFeature.generateCSV(from: rows)
        let lines = csv.components(separatedBy: "\n")

        #expect(lines.count == 2)
        #expect(lines[0] == "Symbol,Name,Category,Net Amount,Price,Value")
        #expect(lines[1].hasPrefix("\"BTC\","))
        #expect(lines[1].contains("\"Bitcoin\""))
    }
}

// MARK: - Share Percent Tests (Issue #9)

struct SharePercentTests {
    // MARK: - NetworksTab

    @Test func `networks tab all positive sum to100 percent`() {
        let positions: [(chain: String?, netUSDValue: Decimal)] = [
            (chain: "ethereum", netUSDValue: 500),
            (chain: "polygon", netUSDValue: 300),
            (chain: "arbitrum", netUSDValue: 200)
        ]

        let rows = NetworksTab.computeRows(from: positions)
        let sum = rows.reduce(Decimal.zero) { $0 + $1.sharePercent }

        #expect(sum == 1, "All-positive shares should sum to 100%, got \(sum)")
    }

    @Test func `networks tab mixed positive negative sum to100 percent`() {
        // Chain A: +100 supply, Chain B: -50 borrow
        // Net portfolio = 100 + (-50) = 50
        // Correct: A = 100/50 = 200%, B = -50/50 = -100%, sum = 100%
        // Bug: totalValue = max(100,0) + max(-50,0) = 100
        //      A = 100/100 = 100%, B = -50/100 = -50%, sum = 50% (broken)
        let positions: [(chain: String?, netUSDValue: Decimal)] = [
            (chain: "ethereum", netUSDValue: 100),
            (chain: "polygon", netUSDValue: -50)
        ]

        let rows = NetworksTab.computeRows(from: positions)
        let sum = rows.reduce(Decimal.zero) { $0 + $1.sharePercent }

        #expect(sum == 1, "Mixed positive/negative shares should sum to 100%, got \(sum)")
    }

    @Test func `networks tab all negative handled gracefully`() {
        // All negative — totalValue should be negative, not clamped to zero
        let positions: [(chain: String?, netUSDValue: Decimal)] = [
            (chain: "ethereum", netUSDValue: -100),
            (chain: "polygon", netUSDValue: -50)
        ]

        let rows = NetworksTab.computeRows(from: positions)

        // Should not crash (no division by zero) and rows should exist
        #expect(rows.count == 2)

        // With all-negative, shares should still sum to 1.0
        // (each share = value / totalValue, where totalValue is negative)
        let sum = rows.reduce(Decimal.zero) { $0 + $1.sharePercent }
        #expect(sum == 1, "All-negative shares should sum to 100%, got \(sum)")
    }

    // MARK: - PlatformsTab

    @Test func `platforms tab mixed positive negative sum to100 percent`() {
        let positions: [PlatformsTab.PlatformInput] = [
            PlatformsTab.PlatformInput(chain: "ethereum", protocolId: "aave-v3", protocolName: "Aave V3", positionType: .lending, netUSDValue: 200),
            PlatformsTab.PlatformInput(chain: "ethereum", protocolId: "compound", protocolName: "Compound", positionType: .lending, netUSDValue: -80)
        ]

        let rows = PlatformsTab.computeRows(from: positions)
        let sum = rows.reduce(Decimal.zero) { $0 + $1.sharePercent }

        #expect(sum == 1, "Platform mixed shares should sum to 100%, got \(sum)")
    }

    // MARK: - Cross-tab consistency

    @Test func `both tabs same calculation strategy`() {
        // Given equivalent inputs, both tabs should produce the same percentage sum
        let netA: Decimal = 300
        let netB: Decimal = -100

        let networkRows = NetworksTab.computeRows(from: [
            (chain: "ethereum", netUSDValue: netA),
            (chain: "polygon", netUSDValue: netB)
        ])

        let platformRows = PlatformsTab.computeRows(from: [
            PlatformsTab.PlatformInput(chain: "ethereum", protocolId: "proto-a", protocolName: "Proto A", positionType: .lending, netUSDValue: netA),
            PlatformsTab.PlatformInput(chain: "polygon", protocolId: "proto-b", protocolName: "Proto B", positionType: .lending, netUSDValue: netB)
        ])

        let networkSum = networkRows.reduce(Decimal.zero) { $0 + $1.sharePercent }
        let platformSum = platformRows.reduce(Decimal.zero) { $0 + $1.sharePercent }

        #expect(networkSum == platformSum, "Both tabs should use the same percentage strategy")
        #expect(networkSum == 1, "Shares should sum to 100%")
    }
}
