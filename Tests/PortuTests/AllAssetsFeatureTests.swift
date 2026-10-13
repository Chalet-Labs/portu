// swiftlint:disable file_length

import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct AllAssetsFeatureTests {
    // MARK: - Tab Selection

    @Test func `tabs offer only implemented asset views`() {
        #expect(AssetTab.allCases == [.assets, .platforms, .networks])
    }

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

    // MARK: - Search Text

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
}

// MARK: - Pure Function Tests

struct AssetRowAggregationTests {
    /// The Assets tab's visible rows for ad-hoc tokens in one wallet.
    private func assetRows(
        _ tokens: [TokenEntry],
        livePricesUSD: [String: Decimal] = [:],
        rate: Decimal = 1) -> [AssetRowData] {
        AllAssetsFeature.assets(
            PortfolioValuationFixture.context(tokens: tokens, rate: rate, livePricesUSD: livePricesUSD),
            searchText: "").rows
    }

    // MARK: - Row Aggregation

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

        let rows = assetRows(tokens)

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

        let rows = assetRows(tokens, livePricesUSD: ["bitcoin": 65000])

        #expect(rows.count == 1)
        #expect(rows[0].price == 65000)
        #expect(rows[0].value == 130_000) // 2 * 65000
        #expect(rows[0].source == .live)
    }

    @Test func `uses live prices keyed by onchain identity when coinGeckoId missing`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let assetId = UUID()
        let tokens: [TokenEntry] = [
            TokenEntry(
                assetId: assetId,
                symbol: "TKN",
                name: "Onchain Token",
                category: .other,
                coinGeckoId: nil,
                onchainIdentity: identity,
                role: .balance,
                amount: 10,
                usdValue: 50)
        ]

        let rows = assetRows(tokens, livePricesUSD: [identity.historicalPriceID: 7])

        #expect(rows.count == 1)
        #expect(rows[0].source == .live)
        #expect(rows[0].price == 7)
        #expect(rows[0].value == 70)
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

        let rows = assetRows(tokens)

        #expect(rows.count == 1)
        #expect(rows[0].source == .sync)
        // V5: the sync value over the amount, 50 / 1_000_000
        #expect(rows[0].price == Decimal(50) / Decimal(1_000_000))
        #expect(rows[0].value == 50)
    }

    @Test func `converts sync-time fallback values once for display currency`() throws {
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

        let rows = try assetRows(tokens, rate: #require(Decimal(string: "0.9")))

        #expect(rows[0].price == Decimal(45) / Decimal(1_000_000))
        #expect(rows[0].value == 45)
    }

    /// The live book is USD and the rate is applied once: 2 × 55,000 × 0.9. Number changes → All
    /// Assets: "The rate is applied once; a CHF live price used to be converted twice."
    @Test func `applies the display rate once to live USD prices`() throws {
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

        let rows = try assetRows(tokens, livePricesUSD: ["bitcoin": 55000], rate: #require(Decimal(string: "0.9")))

        #expect(rows[0].price == 49500)
        #expect(rows[0].value == 99000)
        #expect(rows[0].source == .live)
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

        let rows = assetRows(tokens, livePricesUSD: ["ethereum": 3000])

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

        let rows = assetRows(tokens)

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

        let rows = assetRows(tokens)

        #expect(rows.count == 2)
        let symbols = Set(rows.map(\.symbol))
        #expect(symbols == ["BTC", "ETH"])
    }

    // MARK: - Search Filtering

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

    // MARK: - AssetAccumulator

    @Test func `accumulator struct stores all fields`() {
        let acc = AssetAccumulator(
            symbol: "BTC",
            name: "Bitcoin",
            category: .major,
            coinGeckoId: "bitcoin",
            positive: Decimal(1.5),
            borrow: Decimal(0.3),
            positiveUSD: Decimal(90000),
            borrowUSD: Decimal(18000))

        #expect(acc.symbol == "BTC")
        #expect(acc.name == "Bitcoin")
        #expect(acc.category == .major)
        #expect(acc.coinGeckoId == "bitcoin")
        #expect(acc.positive == Decimal(1.5))
        #expect(acc.borrow == Decimal(0.3))
        #expect(acc.positiveUSD == Decimal(90000))
        #expect(acc.borrowUSD == Decimal(18000))
    }

    @Test func `accumulator defaults numeric fields to zero`() {
        let acc = AssetAccumulator(
            symbol: "ETH",
            name: "Ethereum",
            category: .defi)

        #expect(acc.positive == 0)
        #expect(acc.borrow == 0)
        #expect(acc.positiveUSD == 0)
        #expect(acc.borrowUSD == 0)
        #expect(acc.coinGeckoId == nil)
    }

    // MARK: - CSV Generation

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
    private typealias Seam = AllAssetsSeamFixture

    /// Shares of a net list of sync-valued tokens, one position per token.
    private func networkShares(_ values: [(Chain, Decimal)]) -> [Decimal?] {
        AllAssetsFeature.networks(Seam.context(values.enumerated().map { index, entry in
            Seam.input(
                index + 1,
                protocolID: nil,
                chain: entry.0,
                positionType: .idle,
                role: entry.1 < 0 ? .borrow : .balance,
                usdValue: abs(entry.1))
        })).rows.map(\.share)
    }

    private func platformShares(_ values: [(String, Decimal)]) -> [Decimal?] {
        AllAssetsFeature.platforms(Seam.context(values.enumerated().map { index, entry in
            Seam.input(index + 1, protocolID: entry.0, role: entry.1 < 0 ? .borrow : .balance, usdValue: abs(entry.1))
        })).rows.map(\.share)
    }

    private func sum(_ shares: [Decimal?]) -> Decimal {
        shares.compactMap(\.self).reduce(Decimal.zero, +)
    }

    // MARK: - NetworksTab

    @Test func `networks tab all positive sum to 100 percent`() {
        let shares = networkShares([(.ethereum, 500), (.polygon, 300), (.arbitrum, 200)])

        #expect(sum(shares) == 1, "All-positive shares should sum to 100%, got \(sum(shares))")
    }

    @Test func `networks tab mixed positive negative sum to 100 percent`() {
        // Chain A: +100 supply, Chain B: -50 borrow
        // Net portfolio = 100 + (-50) = 50
        // Correct: A = 100/50 = 200%, B = -50/50 = -100%, sum = 100%
        let shares = networkShares([(.ethereum, 100), (.polygon, -50)])

        #expect(shares == [2, -1])
        #expect(sum(shares) == 1, "Mixed positive/negative shares should sum to 100%, got \(sum(shares))")
    }

    /// F4: a list whose total is not positive shows "—" for every share. Number changes → All
    /// Assets: shares "show '—' for an empty list or a total that is not positive".
    @Test func `networks tab all negative shows no shares`() {
        let shares = networkShares([(.ethereum, -100), (.polygon, -50)])

        #expect(shares.count == 2)
        #expect(shares.allSatisfy { $0 == nil })
    }

    // MARK: - PlatformsTab

    @Test func `platforms tab mixed positive negative sum to 100 percent`() {
        let shares = platformShares([("aave-v3", 200), ("compound", -80)])

        #expect(sum(shares) == 1, "Platform mixed shares should sum to 100%, got \(sum(shares))")
    }

    // MARK: - Cross-tab consistency

    @Test func `both tabs same calculation strategy`() {
        // Given equivalent inputs, both tabs should produce the same percentage sum
        let networkSum = sum(networkShares([(.ethereum, 300), (.polygon, -100)]))
        let platformSum = sum(platformShares([("proto-a", 300), ("proto-b", -100)]))

        #expect(networkSum == platformSum, "Both tabs should use the same percentage strategy")
        #expect(networkSum == 1, "Shares should sum to 100%")
    }
}
