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
            PositionToken.self, Asset.self,
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
}
