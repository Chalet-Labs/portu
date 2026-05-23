import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

@MainActor
struct BackfillRequestTimingTests {
    @Test func `live backfill spaces requests between candidates`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        insertSnapshotOnlyAsset(id: uuid(11), coinGeckoId: "bitcoin", context: context)
        insertSnapshotOnlyAsset(id: uuid(12), coinGeckoId: "ethereum", context: context)
        try context.save()

        var slept: [Duration] = []
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in [
                    HistoricalPriceDTO(
                        coinGeckoId: coinGeckoId,
                        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                        usdPrice: 1)
                ] },
                invalidateCache: {}),
            requestSpacing: .seconds(2),
            sleep: { duration in slept.append(duration) })

        _ = try await client.run()

        #expect(slept == [.seconds(2)])
    }

    @Test func `live backfill retries a rate limited candidate`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        insertSnapshotOnlyAsset(id: uuid(11), coinGeckoId: "bitcoin", context: context)
        try context.save()

        let attempts = SendableCounter()
        var slept: [Duration] = []
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    if attempts.incrementAndGet() == 1 {
                        throw PriceServiceError.rateLimited
                    }
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 1)
                    ]
                },
                invalidateCache: {}),
            requestSpacing: .zero,
            rateLimitRetryDelay: .seconds(60),
            sleep: { duration in slept.append(duration) })

        let result = try await client.run()

        #expect(attempts.value == 2)
        #expect(slept == [.seconds(60)])
        #expect(result.failedCoinGeckoIDs.isEmpty)
        #expect(result.fetchedAssets == 1)
    }

    private func insertSnapshotOnlyAsset(id: UUID, coinGeckoId: String, context: ModelContext) {
        let asset = Asset(id: id, symbol: coinGeckoId.uppercased(), name: coinGeckoId, coinGeckoId: coinGeckoId)
        context.insert(asset)
        context.insert(AssetSnapshot(
            syncBatchId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
            accountId: uuid(201),
            assetId: asset.id,
            symbol: asset.symbol,
            category: .other,
            amount: 1,
            usdValue: 1))
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}

private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func incrementAndGet() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}
