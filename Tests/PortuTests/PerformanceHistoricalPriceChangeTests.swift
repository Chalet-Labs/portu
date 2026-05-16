import Foundation
@testable import Portu
import PortuCore
import Testing

struct PerformanceHistoricalPriceChangeTests {
    @Test func `computes period price changes from first and last cached prices`() {
        let day1 = date(2024, 1, 1)
        let day2 = date(2024, 1, 2)

        let changes = PerformanceFeature.computeHistoricalPriceChanges(
            rows: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day1, usdPrice: 40000),
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day2, usdPrice: 44000),
                HistoricalPriceEntry(coinGeckoId: "ethereum", day: day1, usdPrice: 2000),
                HistoricalPriceEntry(coinGeckoId: "ethereum", day: day2, usdPrice: 1800)
            ])

        #expect(changes.map(\.coinGeckoId) == ["bitcoin", "ethereum"])
        #expect(changes[0].percentChange == Decimal(string: "0.1")!)
        #expect(changes[1].percentChange == Decimal(string: "-0.1")!)
    }

    @Test func `applies asset display names to period price changes`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let changes = [
            AssetPricePeriodChange(
                coinGeckoId: identity.historicalPriceID,
                startPrice: 1,
                endPrice: 2,
                percentChange: 1)
        ]

        let named = PerformanceFeature.applyAssetDisplayNames(
            changes: changes,
            namesByHistoricalPriceID: [
                "zapper:base:0xlocal": "Local Token"
            ])

        #expect(named.first?.coinGeckoId == identity.historicalPriceID)
        #expect(named.first?.name == "Local Token")
    }

    @Test func `filters historical price rows to held ids for selected account`() {
        let account = UUID()
        let other = UUID()
        let btc = UUID()
        let eth = UUID()
        let sol = UUID()
        let empty = UUID()
        let startDate = date(2024, 1, 1)
        let day2 = date(2024, 1, 2)

        let rows = [
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: startDate, usdPrice: 40000),
            HistoricalPriceEntry(coinGeckoId: "ethereum", day: startDate, usdPrice: 2000),
            HistoricalPriceEntry(coinGeckoId: "solana", day: startDate, usdPrice: 100),
            HistoricalPriceEntry(coinGeckoId: "empty", day: startDate, usdPrice: 1),
            HistoricalPriceEntry(coinGeckoId: "cache-only", day: day2, usdPrice: 1)
        ]

        let filtered = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: rows,
            holdings: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: btc,
                    timestamp: startDate,
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: other,
                    assetId: eth,
                    timestamp: startDate,
                    coinGeckoId: "ethereum",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: sol,
                    timestamp: startDate,
                    coinGeckoId: "old-sol",
                    coinGeckoIdOverride: "solana",
                    amount: 1,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: empty,
                    timestamp: startDate,
                    coinGeckoId: "empty",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 1)
            ],
            startDate: startDate,
            accountId: account,
            isHistoricalBackfillEnabled: true)

        #expect(filtered.map(\.coinGeckoId) == ["bitcoin", "solana"])
    }

    @Test func `filters historical price rows to held zapper ids for unmapped onchain assets`() {
        let account = UUID()
        let asset = UUID()
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let startDate = date(2024, 1, 1)

        let filtered = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: [
                HistoricalPriceEntry(coinGeckoId: identity.historicalPriceID, day: startDate, usdPrice: 1.5)
            ],
            holdings: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: startDate,
                    coinGeckoId: nil,
                    coinGeckoIdOverride: nil,
                    onchainIdentity: identity,
                    amount: 2,
                    borrowAmount: 0)
            ],
            startDate: startDate,
            accountId: account,
            isHistoricalBackfillEnabled: true)

        #expect(filtered.map(\.coinGeckoId) == [identity.historicalPriceID])
    }

    @Test func `filters legacy zapper historical rows to canonical held asset ids`() {
        let account = UUID()
        let asset = UUID()
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let startDate = date(2024, 1, 1)

        let filtered = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: [
                HistoricalPriceEntry(coinGeckoId: "zapper:base:0xlocal", day: startDate, usdPrice: 1.5)
            ],
            holdings: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: startDate,
                    coinGeckoId: nil,
                    coinGeckoIdOverride: nil,
                    onchainIdentity: identity,
                    amount: 2,
                    borrowAmount: 0)
            ],
            startDate: startDate,
            accountId: account,
            isHistoricalBackfillEnabled: true)

        #expect(filtered == [
            HistoricalPriceEntry(coinGeckoId: identity.historicalPriceID, day: startDate, usdPrice: 1.5)
        ])
    }

    @Test func `earliest estimate holdings use zapper id when coin gecko id is absent`() {
        let account = UUID()
        let asset = UUID()
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let firstReal = date(2024, 1, 2)

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: firstReal,
                    coinGeckoId: nil,
                    coinGeckoIdOverride: nil,
                    onchainIdentity: identity,
                    amount: 3,
                    borrowAmount: 0)
            ],
            firstRealSnapshotDate: firstReal,
            accountId: account)

        #expect(holdings.map(\.coinGeckoId) == [identity.historicalPriceID])
    }

    @Test func `historical price rows are empty when backfill setting is disabled`() {
        let account = UUID()
        let asset = UUID()
        let startDate = date(2024, 1, 1)

        let filtered = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: startDate, usdPrice: 40000)
            ],
            holdings: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: startDate,
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0)
            ],
            startDate: startDate,
            accountId: account,
            isHistoricalBackfillEnabled: false)

        #expect(filtered.isEmpty)
    }

    @Test func `historical price rows include boundary utc day when range start has time component`() {
        let account = UUID()
        let asset = UUID()
        let day = date(2024, 1, 1)
        let startDate = day.addingTimeInterval(12 * 3600)

        let filtered = PerformanceFeature.historicalPriceEntriesForHeldAssets(
            rows: [
                HistoricalPriceEntry(coinGeckoId: "bitcoin", day: day, usdPrice: 40000)
            ],
            holdings: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: day.addingTimeInterval(8 * 3600),
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0)
            ],
            startDate: startDate,
            accountId: account,
            isHistoricalBackfillEnabled: true)

        #expect(filtered.map(\.coinGeckoId) == ["bitcoin"])
    }

    @Test func `earliest estimate holdings skip zero net rows and prefer overrides`() {
        let account = UUID()
        let zeroNet = UUID()
        let overridden = UUID()
        let firstReal = date(2024, 1, 2)

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: zeroNet,
                    timestamp: firstReal,
                    coinGeckoId: "missing-price",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 1),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: overridden,
                    timestamp: firstReal,
                    coinGeckoId: "old-id",
                    coinGeckoIdOverride: "new-id",
                    amount: 2,
                    borrowAmount: 0)
            ],
            firstRealSnapshotDate: firstReal,
            accountId: account)

        #expect(holdings == [
            HistoricalEstimateHolding(
                accountId: account,
                assetId: overridden,
                coinGeckoId: "new-id",
                amount: 2)
        ])
    }

    @Test func `earliest estimate holdings use first snapshot on first real day`() {
        let account = UUID()
        let asset = UUID()
        let morning = date(2024, 1, 2).addingTimeInterval(8 * 3600)
        let evening = date(2024, 1, 2).addingTimeInterval(20 * 3600)

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: [
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: evening,
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 3,
                    borrowAmount: 0),
                HistoricalEstimateSnapshotEntry(
                    accountId: account,
                    assetId: asset,
                    timestamp: morning,
                    coinGeckoId: "bitcoin",
                    coinGeckoIdOverride: nil,
                    amount: 1,
                    borrowAmount: 0)
            ],
            firstRealSnapshotDate: morning,
            accountId: account)

        #expect(holdings == [
            HistoricalEstimateHolding(
                accountId: account,
                assetId: asset,
                coinGeckoId: "bitcoin",
                amount: 1)
        ])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
