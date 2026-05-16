import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

@MainActor
struct HistoricalPriceBackfillLiveTests {
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
            now: { Date(timeIntervalSince1970: 20) },
            requestSpacing: .zero,
            sleep: { _ in })

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

    @Test func `live backfill includes assets present only in local snapshots`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let soldAsset = Asset(id: uuid(11), symbol: "SOLD", name: "Sold Token", coinGeckoId: "sold-token")
        context.insert(soldAsset)
        context.insert(AssetSnapshot(
            syncBatchId: uuid(101),
            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
            accountId: uuid(201),
            assetId: soldAsset.id,
            symbol: soldAsset.symbol,
            category: .other,
            amount: 4,
            usdValue: 80))
        try context.save()

        let requestedIDs = SendableArray<String>()
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    requestedIDs.append(coinGeckoId)
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 20)
                    ]
                },
                invalidateCache: {}),
            requestSpacing: .zero,
            sleep: { _ in })

        let result = try await client.run()
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())

        #expect(requestedIDs.values == ["sold-token"])
        #expect(result.requestedAssets == 1)
        #expect(result.fetchedAssets == 1)
        #expect(rows.map(\.coinGeckoId) == ["sold-token"])
    }

    @Test func `live backfill skips dashboard ignored dust and unpriced assets before network requests`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .manual)
        let visibleAsset = Asset(id: uuid(21), symbol: "VISIBLE", name: "Visible", coinGeckoId: "visible-token")
        let dustAsset = Asset(id: uuid(22), symbol: "DUST", name: "Dust", coinGeckoId: "dust-token")
        let ignoredAsset = Asset(id: uuid(23), symbol: "IGNORED", name: "Ignored", coinGeckoId: "ignored-token")
        let unpricedAsset = Asset(id: uuid(24), symbol: "UNPRICED", name: "Unpriced", coinGeckoId: "unpriced-token")
        let pinnedDustAsset = Asset(id: uuid(25), symbol: "PINNED", name: "Pinned", coinGeckoId: "pinned-dust")
        let snapshotDustAsset = Asset(id: uuid(26), symbol: "SNAPDUST", name: "Snapshot Dust", coinGeckoId: "snapshot-dust")
        let position = Position(
            positionType: .idle,
            tokens: [
                PositionToken(role: .balance, amount: 2, usdValue: 4, asset: visibleAsset),
                PositionToken(role: .balance, amount: 1, usdValue: 0.50, asset: dustAsset),
                PositionToken(role: .balance, amount: 1, usdValue: 10, asset: ignoredAsset),
                PositionToken(role: .balance, amount: 1, usdValue: 0, asset: unpricedAsset),
                PositionToken(role: .balance, amount: 1, usdValue: 0.25, asset: pinnedDustAsset)
            ],
            account: account)
        account.positions = [position]
        context.insert(account)
        context.insert(snapshotDustAsset)
        context.insert(AssetSnapshot(
            syncBatchId: uuid(102),
            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
            accountId: uuid(202),
            assetId: snapshotDustAsset.id,
            symbol: snapshotDustAsset.symbol,
            category: .other,
            amount: 1,
            usdValue: 0.40))
        context.insert(TokenPricingOverride(assetId: ignoredAsset.id, isIgnored: true))
        context.insert(TokenPricingOverride(assetId: pinnedDustAsset.id, alwaysShow: true))
        try context.save()

        let requestedIDs = SendableArray<String>()
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    requestedIDs.append(coinGeckoId)
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 1)
                    ]
                },
                invalidateCache: {}),
            requestSpacing: .zero,
            sleep: { _ in })

        let result = try await client.run()

        #expect(requestedIDs.values == ["pinned-dust", "visible-token"])
        #expect(result.requestedAssets == 2)
        #expect(result.fetchedAssets == 2)
        #expect(result.skippedAssets == 0)
    }

    @Test func `live backfill resolves missing coingecko ids and uses zapper fallback for unmapped onchain assets`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .manual)
        let mappedAsset = Asset(
            id: uuid(41),
            symbol: "MAP",
            name: "Mapped",
            upsertChain: .ethereum,
            upsertContract: "0xMapped")
        let fallbackAsset = Asset(
            id: uuid(42),
            symbol: "LOCAL",
            name: "Local",
            upsertChain: .base,
            upsertContract: "0xFallback")
        let position = Position(
            positionType: .idle,
            tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 10, asset: mappedAsset),
                PositionToken(role: .balance, amount: 2, usdValue: 20, asset: fallbackAsset)
            ],
            account: account)
        account.positions = [position]
        context.insert(account)
        try context.save()

        let mappedIdentity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xMapped")
        let fallbackIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xFallback")
        let coinGeckoRequests = SendableArray<String>()
        let zapperRequests = SendableArray<OnchainTokenIdentity>()
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    coinGeckoRequests.append(coinGeckoId)
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 5)
                    ]
                },
                resolveCoinGeckoIDs: { identities in
                    #expect(Set(identities) == Set([mappedIdentity, fallbackIdentity]))
                    return [mappedIdentity: "mapped-token"]
                },
                fetchZapperHistoricalPrices: { identity, _ in
                    zapperRequests.append(identity)
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: identity.historicalPriceID,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 6)
                    ]
                },
                invalidateCache: {}),
            requestSpacing: .zero,
            sleep: { _ in })

        let result = try await client.run()
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
            .sorted { $0.coinGeckoId < $1.coinGeckoId }
        let overrides = try context.fetch(FetchDescriptor<TokenPricingOverride>())
        let mappings = try context.fetch(FetchDescriptor<TokenIdentityMapping>())

        #expect(result.requestedAssets == 2)
        #expect(result.fetchedAssets == 2)
        #expect(result.skippedAssets == 0)
        #expect(coinGeckoRequests.values == ["mapped-token"])
        #expect(zapperRequests.values == [fallbackIdentity])
        #expect(rows.map(\.coinGeckoId) == [fallbackIdentity.historicalPriceID, mappedIdentity.historicalPriceID])
        #expect(overrides.isEmpty)
        #expect(mappings.count == 1)
        #expect(mappings.first?.onchainIdentity == mappedIdentity)
        #expect(mappings.first?.coinGeckoId == "mapped-token")
    }

    @Test func `live backfill resolves contract coingecko mappings and stores canonical history`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .manual)
        let identity = OnchainTokenIdentity(
            chain: .arbitrum,
            contractAddress: "0xaf88d065e77c8cc2239327c5edb3a432268e5831")
        let asset = Asset(
            id: uuid(49),
            symbol: "USDC",
            name: "USD Coin",
            upsertChain: identity.chain,
            upsertContract: identity.contractAddress)
        let position = Position(
            positionType: .idle,
            tokens: [PositionToken(role: .balance, amount: 390, usdValue: 390, asset: asset)],
            account: account)
        account.positions = [position]
        context.insert(account)
        try context.save()

        let requestedIDs = SendableArray<String>()
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    requestedIDs.append(coinGeckoId)
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 1)
                    ]
                },
                resolveCoinGeckoIDs: { identities in
                    #expect(identities == [identity])
                    return [identity: "usd-coin"]
                },
                fetchZapperHistoricalPrices: { _, _ in
                    Issue.record("Known contract mappings should not use Zapper fallback")
                    return []
                },
                invalidateCache: {}),
            requestSpacing: .zero,
            sleep: { _ in })

        let result = try await client.run()
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())

        #expect(requestedIDs.values == ["usd-coin"])
        #expect(result.requestedAssets == 1)
        #expect(result.fetchedAssets == 1)
        #expect(rows.map(\.coinGeckoId) == [identity.historicalPriceID])
    }

    @Test func `live backfill reuses cached identity mappings without resolving again`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xMapped")
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .manual)
        let asset = Asset(
            id: uuid(45),
            symbol: "MAP",
            name: "Mapped",
            upsertChain: identity.chain,
            upsertContract: identity.contractAddress)
        let position = Position(
            positionType: .idle,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 10, asset: asset)],
            account: account)
        account.positions = [position]
        context.insert(account)
        context.insert(TokenIdentityMapping(identity: identity, coinGeckoId: "cached-token"))
        try context.save()

        let coinGeckoRequests = SendableArray<String>()
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { coinGeckoId, _ in
                    coinGeckoRequests.append(coinGeckoId)
                    return [
                        HistoricalPriceDTO(
                            coinGeckoId: coinGeckoId,
                            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
                            usdPrice: 5)
                    ]
                },
                resolveCoinGeckoIDs: { identities in
                    #expect(identities.isEmpty)
                    return [:]
                },
                invalidateCache: {}),
            requestSpacing: .zero,
            sleep: { _ in })

        let result = try await client.run()

        #expect(result.requestedAssets == 1)
        #expect(result.fetchedAssets == 1)
        #expect(coinGeckoRequests.values == ["cached-token"])
    }

    @Test func `live backfill skips zapper fallback candidates when zapper provider is unavailable`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .manual)
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xFallback")
        let asset = Asset(
            id: uuid(51),
            symbol: "LOCAL",
            name: "Local",
            upsertChain: identity.chain,
            upsertContract: identity.contractAddress)
        let position = Position(
            positionType: .idle,
            tokens: [PositionToken(role: .balance, amount: 2, usdValue: 20, asset: asset)],
            account: account)
        account.positions = [position]
        context.insert(account)
        try context.save()

        var slept: [Duration] = []
        let zapperRequests = SendableArray<OnchainTokenIdentity>()
        let client = HistoricalPriceBackfillClient.live(
            modelContext: context,
            priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { _, _ in [] },
                resolveCoinGeckoIDs: { _ in [:] },
                fetchZapperHistoricalPrices: { identity, _ in
                    zapperRequests.append(identity)
                    return []
                },
                canFetchZapperHistoricalPrices: { false },
                invalidateCache: {}),
            requestSpacing: .seconds(8),
            sleep: { duration in slept.append(duration) })

        let result = try await client.run()

        #expect(result.requestedAssets == 1)
        #expect(result.fetchedAssets == 0)
        #expect(result.failedCoinGeckoIDs == [identity.historicalPriceID])
        #expect(zapperRequests.values.isEmpty)
        #expect(slept.isEmpty)
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}

private final class SendableArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var values: [Element] {
        lock.withLock { storage }
    }

    func append(_ value: Element) {
        lock.withLock {
            storage.append(value)
        }
    }
}
