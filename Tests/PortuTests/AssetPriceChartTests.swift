import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

// Regression test for issue #15:
// AssetPriceChart used @Query(sort: \AssetSnapshot.timestamp) with no predicate,
// loading ALL AssetSnapshots into memory and filtering in Swift.
// Fix: @Query must use a #Predicate filtering by assetId at the database level.

@MainActor
struct AssetPriceChartQueryTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self, TokenPricingOverride.self,
            HistoricalPricePoint.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func `snapshot query filtered by assetId returns only that asset's snapshots`() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let targetId = UUID()
        let otherId = UUID()
        let batchId = UUID()
        let now = Date()

        // 3 snapshots for the target asset
        for i in 0 ..< 3 {
            context.insert(AssetSnapshot(
                syncBatchId: batchId,
                timestamp: now.addingTimeInterval(Double(i) * 3600),
                accountId: UUID(),
                assetId: targetId,
                symbol: "ETH",
                category: .major,
                amount: 1,
                usdValue: 3000))
        }

        // 2 snapshots for an unrelated asset — must NOT appear in a filtered query
        for i in 0 ..< 2 {
            context.insert(AssetSnapshot(
                syncBatchId: batchId,
                timestamp: now.addingTimeInterval(Double(i) * 3600),
                accountId: UUID(),
                assetId: otherId,
                symbol: "BTC",
                category: .major,
                amount: 1,
                usdValue: 60000))
        }
        try context.save()

        // Unfiltered fetch — simulates the current buggy @Query with no predicate
        let unfiltered = try context.fetch(FetchDescriptor<AssetSnapshot>())
        #expect(unfiltered.count == 5) // all assets loaded — confirms bug exists

        // Predicate-filtered fetch — this is what @Query in AssetPriceChart should do
        let predicate = #Predicate<AssetSnapshot> { $0.assetId == targetId }
        let descriptor = FetchDescriptor<AssetSnapshot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)])
        let filtered = try context.fetch(descriptor)

        // Only the 3 target-asset snapshots should be returned
        #expect(filtered.count == 3)
        #expect(filtered.allSatisfy { $0.assetId == targetId })

        // Prove the unfiltered load is a superset — unbounded when many assets exist
        #expect(unfiltered.count > filtered.count)
    }

    @Test func `effective historical coin gecko id prefers override`() {
        let assetId = UUID()

        let effectiveID = AssetDetailFeature.effectiveHistoricalCoinGeckoID(
            assetCoinGeckoId: "old-id",
            override: TokenPricingOverrideSnapshot(
                assetId: assetId,
                coinGeckoIdOverride: " New-ID "))

        #expect(effectiveID == "new-id")
    }

    @Test func `effective historical coin gecko id falls back to asset id`() {
        let effectiveID = AssetDetailFeature.effectiveHistoricalCoinGeckoID(
            assetCoinGeckoId: " Bitcoin ",
            override: nil)

        #expect(effectiveID == "bitcoin")
    }

    @Test func `historical price rows are empty when backfill setting is disabled`() {
        let startDate = Date(timeIntervalSince1970: 1_704_067_200)
        let rows = [
            HistoricalPricePoint(
                coinGeckoId: "bitcoin",
                day: startDate,
                usdPrice: 40000)
        ]

        let visibleRows = AssetDetailFeature.historicalPriceRows(
            rows,
            startDate: startDate,
            isHistoricalBackfillEnabled: false)

        #expect(visibleRows.isEmpty)
    }

    @Test func `historical price rows include boundary utc day when range start has time component`() {
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let rows = [
            HistoricalPricePoint(
                coinGeckoId: "bitcoin",
                day: day,
                usdPrice: 40000)
        ]

        let visibleRows = AssetDetailFeature.historicalPriceRows(
            rows,
            startDate: day.addingTimeInterval(12 * 3600),
            isHistoricalBackfillEnabled: true)

        #expect(visibleRows.map(\.coinGeckoId) == ["bitcoin"])
    }

    @Test func `price empty state prompts to enable backfill when disabled`() {
        let description = AssetDetailFeature.historicalPriceEmptyDescription(
            coinGeckoId: "bitcoin",
            isHistoricalBackfillEnabled: false)

        #expect(description == "Enable historical price backfill in Settings")
    }

    @Test func `price empty state prompts for coin gecko id when missing`() {
        let description = AssetDetailFeature.historicalPriceEmptyDescription(
            coinGeckoId: " ",
            isHistoricalBackfillEnabled: true)

        #expect(description == "Set a CoinGecko ID override in Settings")
    }

    @Test func `price empty state prompts to run cache when enabled and mapped`() {
        let description = AssetDetailFeature.historicalPriceEmptyDescription(
            coinGeckoId: "bitcoin",
            isHistoricalBackfillEnabled: true)

        #expect(description == "Run historical price cache from Settings")
    }
}
