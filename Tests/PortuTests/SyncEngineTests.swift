import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

// The sync regression suite intentionally keeps its shared SwiftData helpers together.
// swiftlint:disable file_length type_body_length

@MainActor
struct SyncEngineTests {
    /// Use a fresh ModelContainer per test — reusing container.mainContext across
    /// tests causes SIGTRAP due to shared thread-local SwiftData state.
    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self, TokenPricingOverride.self,
            TokenIdentityMapping.self,
            HistoricalPricePoint.self,
            PortfolioCategory.self, CategorySymbolRule.self,
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

    @Test func `sync uses provider combined position fetch`() async throws {
        let context = try makeModelContext()
        let token = makeTokenDTO(
            symbol: "ETH",
            name: "Ethereum",
            amount: 1,
            usdValue: 2000,
            chain: .ethereum,
            contractAddress: OnchainTokenIdentity.nativeAssetSentinel,
            sourceKey: "asset:ethereum:0x0000000000000000000000000000000000000000")
        let provider = CombinedOnlyProvider(positions: [PositionDTO(
            positionType: .idle,
            chain: .ethereum,
            protocolId: nil,
            protocolName: nil,
            protocolLogoURL: nil,
            healthFactor: nil,
            tokens: [token])])
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in provider }))
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        try context.save()

        let result = try await engine.sync()

        #expect(result.failedAccounts.isEmpty)
        #expect(account.positions.count == 1)
        #expect(await provider.fetchPositionsCalled)
    }

    @Test func `provider factory defers Zerion key reads off the main actor`() async throws {
        let secretStore = ThreadRecordingSyncSecretStore()
        try secretStore.set(key: .providerAPIKey(.zapper), value: "legacy-only")
        let factory = ProviderFactory(secretStore: secretStore)
        let context = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [("0xabc", .ethereum)],
            exchangeType: nil)

        let provider = try factory.makeProvider(for: .zerion, context: context)
        #expect(secretStore.getMainThreadFlags.isEmpty)

        await #expect(throws: ZerionError.missingAPIKey) {
            _ = try await provider.fetchPositions(context: context)
        }
        #expect(!secretStore.getMainThreadFlags.isEmpty)
        #expect(secretStore.getMainThreadFlags.allSatisfy { !$0 })
    }

    @Test func `provider factory preserves surviving legacy Zapper accounts as read only`() throws {
        let secretStore = MockSecretStore()
        try secretStore.set(key: .providerAPIKey(.zerion), value: "zerion-key")
        let factory = ProviderFactory(secretStore: secretStore)
        let context = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [("0xabc", nil)],
            exchangeType: nil)

        #expect(throws: SyncError.unsupportedLegacyAccount) {
            _ = try factory.makeProvider(for: .zapper, context: context)
        }
    }

    @Test func `legacy Zapper sync error describes read only account state`() {
        #expect(
            SyncError.unsupportedLegacyAccount.errorDescription ==
                "Legacy Zapper accounts are read-only and cannot be synced; cached positions were preserved")
    }

    @Test func `global sync excludes retained legacy Zapper accounts`() async throws {
        let context = try makeModelContext()
        let provider = StubProvider(balances: [])
        let factory = ProviderFactory(resolver: { dataSource, _ in
            guard dataSource == .zerion else {
                throw SyncTestError.unexpectedLegacySync
            }
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let wallet = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        let legacy = Account(name: "Legacy", kind: .wallet, dataSource: .zapper)
        context.insert(wallet)
        context.insert(legacy)
        try context.save()

        let result = try await engine.sync()

        #expect(result.failedAccounts.isEmpty)
        #expect(wallet.lastSyncedAt != nil)
        #expect(legacy.lastSyncedAt == nil)
        #expect(legacy.lastSyncError == nil)
    }

    @Test func `unsupported legacy Bitcoin wallet preserves its last known positions`() async throws {
        let context = try makeModelContext()
        let secretStore = MockSecretStore()
        try secretStore.set(key: .providerAPIKey(.zerion), value: "test-key")
        let provider = ZerionProvider(client: ZerionAPIClient(apiKey: { "test-key" }))
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(secretStore: secretStore, zerionProvider: provider))
        let asset = Asset(symbol: "BTC", name: "Bitcoin")
        let token = PositionToken(role: .balance, amount: 1, usdValue: 100_000, asset: asset)
        let oldPosition = Position(positionType: .idle, chain: .bitcoin, netUSDValue: 100_000, tokens: [token])
        let account = Account(
            name: "Legacy Bitcoin",
            kind: .wallet,
            dataSource: .zerion,
            positions: [oldPosition])
        account.addresses = [WalletAddress(chain: .bitcoin, address: "fixture-bitcoin", account: account)]
        context.insert(account)
        try context.save()

        await #expect(throws: SyncError.allAccountsFailed) {
            _ = try await engine.sync()
        }

        #expect(account.positions.map(\.id) == [oldPosition.id])
        #expect(account.lastSyncError?.contains("bitcoin") == true)
    }

    // MARK: - Error Persistence

    /// Regression test for: lastSyncError is set in memory but never saved before
    /// allAccountsFailed is thrown. A fresh context sees nil instead of the error.
    @Test func `lastSyncError persisted when all syncable accounts fail`() async throws {
        let (context, engine) = try makeTestContext()

        // Zerion account with no API key reaches the provider, which fails before networking.
        let account = Account(name: "My Wallet", kind: .wallet, dataSource: .zerion)
        account.addresses = [WalletAddress(chain: .ethereum, address: "0xabc", account: account)]
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

    @Test func `chain contract dedup normalizes evm casing but preserves solana casing`() throws {
        let (context, engine) = try makeTestContext()
        let ethereumAsset = Asset(symbol: "OLD", name: "Old", upsertChain: .ethereum, upsertContract: "0xAbC")
        let solanaAsset = Asset(symbol: "SOL", name: "Solana", upsertChain: .solana, upsertContract: "AbC")
        [ethereumAsset, solanaAsset].forEach(context.insert)
        try context.save()

        let ethereumMatch = try engine.upsertAsset(from: makeTokenDTO(symbol: "NEW", name: "New", chain: .ethereum, contractAddress: "0xabc"))
        let solanaDistinct = try engine.upsertAsset(from: makeTokenDTO(symbol: "SOL2", name: "Solana 2", chain: .solana, contractAddress: "abc"))

        #expect(ethereumMatch === ethereumAsset)
        #expect(solanaDistinct !== solanaAsset)

        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 3)
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
        let account = Account(name: "Test Wallet", kind: .wallet, dataSource: .zerion, positions: [oldPosition])
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
        let account = Account(name: "Test Wallet", kind: .wallet, dataSource: .zerion, positions: [oldPosition])
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
        let account = Account(name: "Test Wallet", kind: .wallet, dataSource: .zerion, positions: [oldPosition])
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

    @Test func `large successful rebuild clears stale sync error promptly`() async throws {
        let assetCount = 1200
        let balances = (0 ..< assetCount).map { index in
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(
                    symbol: "TOK\(index)",
                    name: "Token \(index)",
                    amount: 1,
                    usdValue: Decimal(index + 1),
                    chain: .ethereum,
                    contractAddress: "0xtoken\(index)")])
        }
        let (context, engine) = try makeMockContext(balances: balances)

        for index in 0 ..< assetCount {
            context.insert(Asset(
                symbol: "OLD\(index)",
                name: "Old Token \(index)",
                upsertChain: .ethereum,
                upsertContract: "0xtoken\(index)"))
        }
        let account = Account(
            name: "Large Wallet",
            kind: .wallet,
            dataSource: .zerion,
            lastSyncError: "Zerion API error: Payment required")
        context.insert(account)
        try context.save()

        let start = ContinuousClock.now
        let result = try await engine.sync()
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(elapsed < .seconds(30))
        #expect(result.failedAccounts.isEmpty)

        let freshContext = ModelContext(context.container)
        let fetched = try #require(try freshContext.fetch(FetchDescriptor<Account>()).first)
        #expect(fetched.lastSyncError == nil)
        #expect(fetched.positions.count == assetCount)
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

private final class ThreadRecordingSyncSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private var getMainThreadFlagsStorage: [Bool] = []

    var getMainThreadFlags: [Bool] {
        lock.withLock { getMainThreadFlagsStorage }
    }

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        lock.withLock {
            getMainThreadFlagsStorage.append(Thread.isMainThread)
            return store[key.rawKey]
        }
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        lock.withLock { store[key.rawKey] = value }
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        _ = lock.withLock { store.removeValue(forKey: key.rawKey) }
    }
}

// MARK: - StubProvider

/// Actor type to match the `PortfolioDataProvider` actor pattern used by real
/// providers (ZerionProvider, ExchangeProvider) per the project guidelines.
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
    case unexpectedLegacySync
}

private actor CombinedOnlyProvider: PortfolioDataProvider {
    nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities(supportsTokenBalances: true, supportsDeFiPositions: true)
    }

    let positions: [PositionDTO]
    var fetchPositionsCalled = false

    init(positions: [PositionDTO]) {
        self.positions = positions
    }

    func fetchPositions(context _: SyncContext) async throws -> [PositionDTO] {
        fetchPositionsCalled = true
        return positions
    }

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        Issue.record("SyncEngine should use the combined provider operation")
        return []
    }
}

// swiftlint:enable file_length type_body_length
