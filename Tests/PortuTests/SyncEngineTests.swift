import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct SyncEngineTests {
    private func makeTestContext() throws -> (ModelContext, SyncEngine) {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        // Use a fresh ModelContext per test — container.mainContext shares thread-local
        // state across tests which causes SIGTRAP when multiple containers exist.
        let context = ModelContext(container)
        let mockStore = MockSecretStore()
        let engine = SyncEngine(modelContext: context, secretStore: mockStore)
        return (context, engine)
    }

    @Test func `sync with no accounts throws`() async throws {
        let (_, engine) = try makeTestContext()
        do {
            _ = try await engine.sync()
            Issue.record("Expected SyncError.noActiveAccounts")
        } catch let error as SyncError {
            #expect(error == .noActiveAccounts)
        }
    }

    @Test func `sync manual only accounts creates snapshots`() async throws {
        let (context, engine) = try makeTestContext()
        let asset = Asset(symbol: "GOLD", name: "Gold Token", category: .other)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 100, usdValue: 5000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 5000, tokens: [token])
        let account = Account(name: "Manual", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        let result = try await engine.sync()

        let snapshots = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots[0].totalValue == 5000)
        #expect(snapshots[0].isPartial == false)
        #expect(result.failedAccounts.isEmpty)
    }

    // MARK: - Upsert Backfill & Dedup

    @Test func `backfill sets chain and contract when nil`() throws {
        let (context, engine) = try makeTestContext()

        // Pre-existing asset with no chain/contract (e.g. first seen via coinGeckoId)
        let asset = Asset(symbol: "UNI", name: "Uniswap", coinGeckoId: "uniswap")
        context.insert(asset)
        try context.save()

        #expect(asset.upsertChain == nil)
        #expect(asset.upsertContract == nil)

        // A DTO arrives with the same coinGeckoId plus chain/contract info
        let dto = makeTokenDTO(
            symbol: "UNI", name: "Uniswap",
            chain: .ethereum, contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",
            coinGeckoId: "uniswap")
        let result = engine.upsertAsset(from: dto)

        // Should reuse existing asset (not create a new one)
        #expect(result.id == asset.id)
        // Backfill: chain and contract should now be filled
        #expect(asset.upsertChain == .ethereum)
        #expect(asset.upsertContract == "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984")
    }

    @Test func `backfill does not overwrite existing chain and contract`() throws {
        let (context, engine) = try makeTestContext()

        let asset = Asset(
            symbol: "WETH", name: "Wrapped Ether",
            coinGeckoId: "weth",
            upsertChain: .ethereum, upsertContract: "0xoriginal")
        context.insert(asset)
        try context.save()

        // DTO with same coinGeckoId but different chain/contract
        let dto = makeTokenDTO(
            symbol: "WETH", name: "Wrapped Ether",
            chain: .polygon, contractAddress: "0xdifferent",
            coinGeckoId: "weth")
        let result = engine.upsertAsset(from: dto)

        #expect(result.id == asset.id)
        // Original values must be preserved (append-only)
        #expect(asset.upsertChain == .ethereum)
        #expect(asset.upsertContract == "0xoriginal")
    }

    @Test func `cross-tier dedup coinGeckoId first then chain contract`() throws {
        let (context, engine) = try makeTestContext()

        // DTO-A: has coinGeckoId + chain/contract
        let dtoA = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc",
            coinGeckoId: "ethereum")
        _ = engine.upsertAsset(from: dtoA)

        // DTO-B: same chain/contract, no coinGeckoId
        let dtoB = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc")
        _ = engine.upsertAsset(from: dtoB)

        let allAssets = try context.fetch(FetchDescriptor<Asset>())
        #expect(allAssets.count == 1)
    }

    @Test func `cross-tier dedup chain contract first then coinGeckoId`() throws {
        let (context, engine) = try makeTestContext()

        // DTO-A: chain/contract only, no coinGeckoId
        let dtoA = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc")
        _ = engine.upsertAsset(from: dtoA)

        // DTO-B: same chain/contract + coinGeckoId
        let dtoB = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc",
            coinGeckoId: "ethereum")
        _ = engine.upsertAsset(from: dtoB)

        let allAssets = try context.fetch(FetchDescriptor<Asset>())
        #expect(allAssets.count == 1)
    }

    // MARK: - Helpers

    private func makeTokenDTO(
        role: TokenRole = .balance,
        symbol: String = "TEST",
        name: String = "Test Token",
        amount: Decimal = 100,
        usdValue: Decimal = 100,
        chain: Chain? = nil,
        contractAddress: String? = nil,
        debankId: String? = nil,
        coinGeckoId: String? = nil,
        sourceKey: String? = nil,
        logoURL: String? = nil,
        category: AssetCategory = .other,
        isVerified: Bool = false) -> TokenDTO {
        TokenDTO(
            role: role, symbol: symbol, name: name,
            amount: amount, usdValue: usdValue,
            chain: chain, contractAddress: contractAddress,
            debankId: debankId, coinGeckoId: coinGeckoId,
            sourceKey: sourceKey, logoURL: logoURL,
            category: category, isVerified: isVerified)
    }

    // MARK: - Snapshots

    @Test func `snapshot batch ids link correctly`() async throws {
        let (context, engine) = try makeTestContext()
        let asset = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 10, usdValue: 25000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 25000, tokens: [token])
        let account = Account(name: "Wallet A", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        let result = try await engine.sync()

        let portfolioSnaps = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        let accountSnaps = try context.fetch(FetchDescriptor<AccountSnapshot>())
        let assetSnaps = try context.fetch(FetchDescriptor<AssetSnapshot>())

        #expect(portfolioSnaps.count == 1)
        #expect(accountSnaps.count == 1)
        #expect(assetSnaps.count == 1)

        let batchId = portfolioSnaps[0].syncBatchId
        #expect(accountSnaps[0].syncBatchId == batchId)
        #expect(assetSnaps[0].syncBatchId == batchId)
        #expect(accountSnaps[0].accountId == account.id)
        #expect(assetSnaps[0].assetId == asset.id)
        #expect(assetSnaps[0].symbol == "ETH")
        #expect(result.failedAccounts.isEmpty)
    }
}

// MARK: - MockSecretStore

private final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func get(key: String) throws(KeychainError) -> String? {
        store[key]
    }

    func set(key: String, value: String) throws(KeychainError) {
        store[key] = value
    }

    func delete(key: String) throws(KeychainError) {
        store.removeValue(forKey: key)
    }
}
