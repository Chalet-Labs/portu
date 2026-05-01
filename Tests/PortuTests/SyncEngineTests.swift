import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

@MainActor
struct SyncEngineTests {
    /// Use a fresh ModelContainer per test — reusing container.mainContext across
    /// tests causes SIGTRAP due to shared thread-local SwiftData state.
    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTestContext() throws -> (ModelContext, SyncEngine) {
        let context = try makeModelContext()
        let factory = ProviderFactory(secretStore: MockSecretStore())
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
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

    // MARK: - Error Persistence

    /// Regression test for: lastSyncError is set in memory but never saved before
    /// allAccountsFailed is thrown. A fresh context sees nil instead of the error.
    @Test func `lastSyncError persisted when all syncable accounts fail`() async throws {
        let (context, engine) = try makeTestContext()

        // Zapper account with no API key in MockSecretStore → resolveProvider throws missingAPIKey
        let account = Account(name: "My Wallet", kind: .wallet, dataSource: .zapper)
        context.insert(account)
        try context.save()

        do {
            _ = try await engine.sync()
            Issue.record("Expected SyncError.allAccountsFailed")
        } catch let error as SyncError {
            #expect(error == .allAccountsFailed)
        }

        // Verify via fresh context — confirms error state was written to the store.
        // Previously, save() was not called before throwing allAccountsFailed, so
        // lastSyncError remained nil in the persistent store despite being set in memory.
        let freshContext = ModelContext(context.container)
        let accounts = try freshContext.fetch(FetchDescriptor<Account>())
        let fetched = try #require(accounts.first)
        #expect(fetched.lastSyncError != nil)
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
        let result = try engine.upsertAsset(from: dto)

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
        let result = try engine.upsertAsset(from: dto)

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
        _ = try engine.upsertAsset(from: dtoA)

        // DTO-B: same chain/contract, no coinGeckoId
        let dtoB = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc")
        _ = try engine.upsertAsset(from: dtoB)

        let allAssets = try context.fetch(FetchDescriptor<Asset>())
        #expect(allAssets.count == 1)
    }

    @Test func `cross-tier dedup chain contract first then coinGeckoId`() throws {
        let (context, engine) = try makeTestContext()

        // DTO-A: chain/contract only, no coinGeckoId
        let dtoA = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc")
        _ = try engine.upsertAsset(from: dtoA)

        // DTO-B: same chain/contract + coinGeckoId
        let dtoB = makeTokenDTO(
            symbol: "ETH", name: "Ethereum",
            chain: .ethereum, contractAddress: "0xabc",
            coinGeckoId: "ethereum")
        _ = try engine.upsertAsset(from: dtoB)

        let allAssets = try context.fetch(FetchDescriptor<Asset>())
        #expect(allAssets.count == 1)
    }

    // MARK: - Transactional Isolation (#31)

    /// Issue #31: If upsertAsset throws mid-rebuild, existing positions
    /// must survive — the commit-phase delete must not have executed.
    @Test func `failed rebuild preserves existing positions`() async throws {
        let balances = [
            PositionDTO(
                positionType: .idle, chain: .ethereum,
                protocolId: nil, protocolName: nil, protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")]),
            PositionDTO(
                positionType: .idle, chain: .ethereum,
                protocolId: nil, protocolName: nil, protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin")])
        ]
        let (context, engine) = try makeThrowingContext(balances: balances, throwAfter: 1)

        // Pre-populate: account has one existing position
        let oldAsset = Asset(symbol: "OLD", name: "Old Token", category: .other)
        context.insert(oldAsset)
        let oldToken = PositionToken(role: .balance, amount: 50, usdValue: 1000, asset: oldAsset)
        let oldPosition = Position(positionType: .idle, netUSDValue: 1000, tokens: [oldToken])
        let account = Account(name: "Test Wallet", kind: .wallet, dataSource: .zapper, positions: [oldPosition])
        context.insert(account)
        try context.save()

        // Sync — first upsertAsset succeeds, second throws
        do {
            _ = try await engine.sync()
            Issue.record("Expected SyncError.allAccountsFailed")
        } catch let error as SyncError {
            #expect(error == .allAccountsFailed)
        }

        // Verify via fresh context: original position must survive
        let freshContext = ModelContext(context.container)
        let accounts = try freshContext.fetch(FetchDescriptor<Account>())
        let fetched = try #require(accounts.first)

        #expect(fetched.positions.count == 1, "Original position must survive failed rebuild")
        #expect(fetched.positions.first?.tokens.first?.asset?.symbol == "OLD")
        #expect(fetched.lastSyncError != nil, "Error must be recorded")

        // No orphan PositionToken rows from the build phase
        let allTokens = try freshContext.fetch(FetchDescriptor<PositionToken>())
        #expect(allTokens.count == 1, "No orphan tokens from staged build phase")
    }

    /// Boundary case: upsertAsset throws on the very first call. The build
    /// phase stages nothing, so the commit phase is a no-op and existing
    /// positions remain intact.
    @Test func `failed rebuild on first upsert preserves existing positions`() async throws {
        let balances = [
            PositionDTO(
                positionType: .idle, chain: .ethereum,
                protocolId: nil, protocolName: nil, protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ]
        let (context, engine) = try makeThrowingContext(balances: balances, throwAfter: 0)

        let oldAsset = Asset(symbol: "OLD", name: "Old Token", category: .other)
        context.insert(oldAsset)
        let oldToken = PositionToken(role: .balance, amount: 50, usdValue: 1000, asset: oldAsset)
        let oldPosition = Position(positionType: .idle, netUSDValue: 1000, tokens: [oldToken])
        let account = Account(name: "Test Wallet", kind: .wallet, dataSource: .zapper, positions: [oldPosition])
        context.insert(account)
        try context.save()

        do {
            _ = try await engine.sync()
            Issue.record("Expected SyncError.allAccountsFailed")
        } catch let error as SyncError {
            #expect(error == .allAccountsFailed)
        }

        let freshContext = ModelContext(context.container)
        let accounts = try freshContext.fetch(FetchDescriptor<Account>())
        let fetched = try #require(accounts.first)

        #expect(fetched.positions.count == 1)
        #expect(fetched.positions.first?.tokens.first?.asset?.symbol == "OLD")
        #expect(fetched.lastSyncError != nil)

        let allTokens = try freshContext.fetch(FetchDescriptor<PositionToken>())
        #expect(allTokens.count == 1, "No orphan tokens from staged build phase")
    }

    @Test func `successful rebuild replaces positions`() async throws {
        let balances = [
            PositionDTO(
                positionType: .idle, chain: .ethereum,
                protocolId: nil, protocolName: nil, protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", amount: 10, usdValue: 25000, coinGeckoId: "ethereum")]),
            PositionDTO(
                positionType: .lending, chain: .ethereum,
                protocolId: "aave-v3", protocolName: "Aave V3", protocolLogoURL: nil,
                healthFactor: 1.5,
                tokens: [makeTokenDTO(symbol: "USDC", name: "USD Coin", amount: 5000, usdValue: 5000, coinGeckoId: "usd-coin")])
        ]
        let (context, engine) = try makeMockContext(balances: balances)

        // Pre-populate: account has one old position
        let oldAsset = Asset(symbol: "OLD", name: "Old Token", category: .other)
        context.insert(oldAsset)
        let oldToken = PositionToken(role: .balance, amount: 50, usdValue: 1000, asset: oldAsset)
        let oldPosition = Position(positionType: .idle, netUSDValue: 1000, tokens: [oldToken])
        let account = Account(name: "Test Wallet", kind: .wallet, dataSource: .zapper, positions: [oldPosition])
        context.insert(account)
        try context.save()

        let result = try await engine.sync()

        // Old position replaced with 2 new ones
        let freshContext = ModelContext(context.container)
        let accounts = try freshContext.fetch(FetchDescriptor<Account>())
        let fetched = try #require(accounts.first)

        #expect(fetched.positions.count == 2)
        let symbols = Set(fetched.positions.compactMap { $0.tokens.first?.asset?.symbol })
        #expect(symbols.contains("ETH"))
        #expect(symbols.contains("USDC"))
        #expect(fetched.lastSyncError == nil)
        #expect(fetched.lastSyncedAt != nil)
        #expect(result.failedAccounts.isEmpty)
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

    private func makeMockContext(balances: [PositionDTO]) throws -> (ModelContext, SyncEngine) {
        let context = try makeModelContext()
        let provider = StubProvider(balances: balances)
        let factory = ProviderFactory(resolver: { _, _ in provider })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        return (context, engine)
    }

    private func makeThrowingContext(
        balances: [PositionDTO],
        throwAfter: Int) throws -> (ModelContext, SyncEngine) {
        let context = try makeModelContext()
        let provider = StubProvider(balances: balances)
        let factory = ProviderFactory(resolver: { _, _ in provider })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        var upsertCount = 0
        engine.upsertAssetOverride = { dto in
            upsertCount += 1
            if upsertCount > throwAfter {
                throw SyncTestError.forcedUpsertFailure
            }
            let asset = Asset(symbol: dto.symbol, name: dto.name, category: dto.category)
            context.insert(asset)
            return asset
        }
        return (context, engine)
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
    func get(key: KeychainKey) throws(KeychainError) -> String? {
        store[key.rawKey]
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        store[key.rawKey] = value
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        store.removeValue(forKey: key.rawKey)
    }
}

// MARK: - StubProvider

/// Actor type to match the `PortfolioDataProvider` actor pattern used by real
/// providers (ZapperProvider, ExchangeProvider) per the project guidelines.
private actor StubProvider: PortfolioDataProvider {
    nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities()
    }

    let balances: [PositionDTO]

    init(balances: [PositionDTO]) {
        self.balances = balances
    }

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        balances
    }
}

private enum SyncTestError: Error {
    case forcedUpsertFailure
}
