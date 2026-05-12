import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct HistoricalPriceBackfillFeatureTests {
    @Test func `candidate selection prefers overrides and skips manual only assets`() {
        let bitcoin = token(assetId: uuid(1), symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 60000)
        let mapped = token(assetId: uuid(2), symbol: "MAP", coinGeckoId: "old-id", amount: 2, usdValue: 20)
        let manualOnly = token(assetId: uuid(3), symbol: "MANUAL", amount: 3, usdValue: 0)
        let noPrice = token(assetId: uuid(4), symbol: "LOCAL", amount: 1, usdValue: 5)

        let candidates = HistoricalBackfillCandidateResolver.candidates(
            tokens: [bitcoin, mapped, manualOnly, noPrice],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: "new-id"),
                TokenPricingOverrideSnapshot(assetId: manualOnly.assetId, manualPriceUSD: 1.25)
            ])

        #expect(candidates.map(\.coinGeckoId) == ["bitcoin", "new-id"])
        #expect(candidates.map(\.assetIds) == [[bitcoin.assetId], [mapped.assetId]])
    }

    @Test func `candidate selection groups assets by normalized coingecko id`() {
        let first = token(assetId: uuid(1), symbol: "AAVE", coinGeckoId: " AAVE ", amount: 1, usdValue: 100)
        let second = token(assetId: uuid(2), symbol: "AAVE.e", coinGeckoId: "aave", amount: 2, usdValue: 200)

        let candidates = HistoricalBackfillCandidateResolver.candidates(tokens: [second, first], overrides: [])

        #expect(candidates.count == 1)
        #expect(candidates.first?.coinGeckoId == "aave")
        #expect(candidates.first?.assetIds == [first.assetId, second.assetId])
    }

    @Test func `cache writer upserts by coin gecko id and day`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        context.insert(HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            usdPrice: 40000,
            fetchedAt: Date(timeIntervalSince1970: 10)))
        try context.save()

        let result = try HistoricalPriceCacheWriter.upsert(
            [
                HistoricalPriceDTO(coinGeckoId: "bitcoin", timestamp: day.addingTimeInterval(3600), usdPrice: 41000),
                HistoricalPriceDTO(coinGeckoId: "ethereum", timestamp: day, usdPrice: 2500)
            ],
            in: context,
            fetchedAt: Date(timeIntervalSince1970: 20))

        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
            .sorted { $0.coinGeckoId < $1.coinGeckoId }
        #expect(result.inserted == 1)
        #expect(result.updated == 1)
        #expect(rows.count == 2)
        #expect(rows[0].coinGeckoId == "bitcoin")
        #expect(rows[0].usdPrice == 41000)
        #expect(rows[0].fetchedAt == Date(timeIntervalSince1970: 20))
        #expect(rows[1].coinGeckoId == "ethereum")
    }

    @Test func `cache writer converges duplicate existing rows for same coin gecko id and day`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        context.insert(HistoricalPricePoint(
            coinGeckoId: " Bitcoin ",
            day: day,
            usdPrice: 40000,
            fetchedAt: Date(timeIntervalSince1970: 10)))
        context.insert(HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day.addingTimeInterval(3600),
            usdPrice: 40500,
            fetchedAt: Date(timeIntervalSince1970: 15)))
        try context.save()

        let result = try HistoricalPriceCacheWriter.upsert(
            [
                HistoricalPriceDTO(coinGeckoId: "BITCOIN", timestamp: day.addingTimeInterval(7200), usdPrice: 41000)
            ],
            in: context,
            fetchedAt: Date(timeIntervalSince1970: 20))

        let rowsForKey = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
            .filter {
                $0.coinGeckoId == "bitcoin" &&
                    $0.day == HistoricalPriceCalendar.utcStartOfDay(for: day)
            }
        #expect(result.inserted == 0)
        #expect(result.updated == 1)
        #expect(rowsForKey.count == 1)
        #expect(rowsForKey.first?.usdPrice == 41000)
        #expect(rowsForKey.first?.fetchedAt == Date(timeIntervalSince1970: 20))
    }

    @Test func `clear cache removes only historical price points`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        context.insert(HistoricalPricePoint(coinGeckoId: "bitcoin", day: Date(), usdPrice: 1))
        context.insert(Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin"))
        try context.save()

        try HistoricalPriceCacheWriter.clear(in: context)

        #expect(try context.fetch(FetchDescriptor<HistoricalPricePoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    @Test func `live backfill result counts grouped asset ids`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .manual)
        let firstAsset = Asset(id: uuid(1), symbol: "AAVE", name: "Aave", coinGeckoId: "aave")
        let secondAsset = Asset(id: uuid(2), symbol: "AAVE.e", name: "Aave", coinGeckoId: "aave")
        let failingAsset = Asset(id: uuid(3), symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")
        let position = Position(
            positionType: .idle,
            tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 100, asset: firstAsset),
                PositionToken(role: .balance, amount: 2, usdValue: 200, asset: secondAsset),
                PositionToken(role: .balance, amount: 3, usdValue: 300, asset: failingAsset)
            ],
            account: account)
        account.positions = [position]
        context.insert(account)
        try context.save()

        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    if coinGeckoId == "ethereum" {
                        throw HistoricalBackfillError(message: "network failed")
                    }
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 90)
                    ]
                },
                invalidateCache: {}),
            now: { Date(timeIntervalSince1970: 20) })

        let result = try await client.run()
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())

        #expect(result.requestedAssets == 3)
        #expect(result.fetchedAssets == 2)
        #expect(result.failedCoinGeckoIDs == ["ethereum"])
        #expect(result.insertedPoints == 1)
        #expect(result.updatedPoints == 0)
        #expect(rows.count == 1)
        #expect(rows.first?.coinGeckoId == "aave")
        #expect(rows.first?.fetchedAt == Date(timeIntervalSince1970: 20))
    }

    @Test func `backfill failure preserves thrown dependency message`() async {
        let store = TestStore(initialState: HistoricalPriceBackfillFeature.State()) {
            HistoricalPriceBackfillFeature()
        } withDependencies: {
            $0.historicalPriceBackfill.run = { throw HistoricalBackfillError(message: "boom") }
        }

        await store.send(.backfillButtonTapped) {
            $0.status = .running
        }
        await store.receive(\.backfillCompleted) {
            $0.status = .failed("boom")
        }
    }

    @Test func `clear cache failure preserves thrown dependency message`() async {
        let store = TestStore(initialState: HistoricalPriceBackfillFeature.State()) {
            HistoricalPriceBackfillFeature()
        } withDependencies: {
            $0.historicalPriceBackfill.clearCache = { throw HistoricalBackfillError(message: "cache boom") }
        }

        await store.send(.clearCacheButtonTapped)
        await store.receive(\.clearCacheCompleted) {
            $0.status = .failed("cache boom")
        }
    }

    @Test func `clear cache tap is ignored while backfill is running`() async {
        var clearCallCount = 0
        let store = TestStore(initialState: HistoricalPriceBackfillFeature.State(status: .running)) {
            HistoricalPriceBackfillFeature()
        } withDependencies: {
            $0.historicalPriceBackfill.clearCache = {
                clearCallCount += 1
            }
        }

        await store.send(.clearCacheButtonTapped)

        #expect(store.state.status == .running)
        #expect(clearCallCount == 0)
    }

    private func token(
        assetId: UUID,
        symbol: String,
        coinGeckoId: String? = nil,
        amount: Decimal,
        usdValue: Decimal) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: .other,
            portfolioCategory: nil,
            coinGeckoId: coinGeckoId,
            role: .balance,
            amount: amount,
            usdValue: usdValue)
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}
