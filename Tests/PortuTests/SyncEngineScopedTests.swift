import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Synchronization
import Testing

@MainActor
struct SyncEngineScopedTests {
    @Test func `scheduled onchain sync is a no op when only legacy wallets remain`() async throws {
        let context = try makeModelContext()
        let legacy = Account(name: "Legacy", kind: .wallet, dataSource: .zapper)
        context.insert(legacy)
        try context.save()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in
                Issue.record("An empty scoped sync must not resolve a provider")
                return ScopedSyncStubProvider(balances: [])
            }))

        let result = try await engine.sync(scope: .onchain)

        #expect(result.failedAccounts.isEmpty)
        #expect(legacy.lastSyncedAt == nil)
        #expect(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).isEmpty)
    }

    @Test func `scoped onchain sync fetches only Zerion accounts`() async throws {
        let context = try makeModelContext()
        let provider = ScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let resolvedSources = Mutex<[DataSource]>([])
        let factory = ProviderFactory(resolver: { dataSource, _ in
            resolvedSources.withLock { $0.append(dataSource) }
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let wallet = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        let legacy = Account(name: "Legacy", kind: .wallet, dataSource: .zapper)
        let exchange = Account(name: "Kraken", kind: .exchange, exchangeType: .kraken, dataSource: .exchange)
        context.insert(wallet)
        context.insert(legacy)
        context.insert(exchange)
        try context.save()

        let result = try await engine.sync(scope: .onchain)

        #expect(resolvedSources.withLock { $0 } == [.zerion])
        #expect(wallet.lastSyncedAt != nil)
        #expect(legacy.lastSyncedAt == nil)
        #expect(exchange.lastSyncedAt == nil)
        #expect(result.failedAccounts.isEmpty)
        let accountSnapshots = try context.fetch(FetchDescriptor<AccountSnapshot>())
        #expect(accountSnapshots.count == 3)
        #expect(accountSnapshots.first { $0.accountId == legacy.id }?.isFresh == false)
    }

    @Test func `scoped exchange sync fetches only exchange accounts`() async throws {
        let context = try makeModelContext()
        let provider = ScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: nil,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin")])
        ])
        let resolvedSources = Mutex<[DataSource]>([])
        let factory = ProviderFactory(resolver: { dataSource, _ in
            resolvedSources.withLock { $0.append(dataSource) }
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let wallet = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        let exchange = Account(name: "Kraken", kind: .exchange, exchangeType: .kraken, dataSource: .exchange)
        context.insert(wallet)
        context.insert(exchange)
        try context.save()

        let result = try await engine.sync(scope: .exchange)

        #expect(resolvedSources.withLock { $0 } == [.exchange])
        #expect(wallet.lastSyncedAt == nil)
        #expect(exchange.lastSyncedAt != nil)
        #expect(result.failedAccounts.isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 2)
    }

    @Test func `scoped sync snapshots cached assets from retained legacy wallets`() async throws {
        let context = try makeModelContext()
        let provider = ScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in provider }))
        let refreshed = Account(name: "Refreshed", kind: .wallet, dataSource: .zerion)
        refreshed.addresses = [WalletAddress(address: "0xrefreshed", account: refreshed)]

        let retainedAsset = Asset(symbol: "LEGACY", name: "Legacy Asset", category: .other)
        let retainedToken = PositionToken(
            role: .balance,
            amount: 2,
            usdValue: 50,
            asset: retainedAsset)
        let retainedPosition = Position(
            positionType: .lending,
            chain: .solana,
            netUSDValue: 50,
            tokens: [retainedToken])
        let retained = Account(name: "Retained", kind: .wallet, dataSource: .zapper)
        retained.positions = [retainedPosition]

        context.insert(retainedAsset)
        context.insert(refreshed)
        context.insert(retained)
        try context.save()

        _ = try await engine.sync(scope: .onchain)

        let snapshots = try context.fetch(FetchDescriptor<AssetSnapshot>())
        let retainedSnapshot = try #require(snapshots.first { $0.accountId == retained.id })
        #expect(retainedSnapshot.assetId == retainedAsset.id)
        #expect(retainedSnapshot.amount == 2)
        #expect(retainedSnapshot.usdValue == 50)
    }

    @Test func `account scoped sync fetches only selected account`() async throws {
        let context = try makeModelContext()
        let provider = ScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let resolvedAccountIDs = Mutex<[UUID]>([])
        let factory = ProviderFactory(resolver: { _, context in
            resolvedAccountIDs.withLock { $0.append(context.accountId) }
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zerion)
        selected.addresses = [WalletAddress(address: "0xselected", account: selected)]
        let staleAsset = Asset(symbol: "OLD", name: "Old Token", category: .major)
        let staleToken = PositionToken(role: .balance, amount: 1, usdValue: 100, asset: staleAsset)
        let stalePosition = Position(positionType: .idle, chain: .ethereum, netUSDValue: 100, tokens: [staleToken])
        let other = Account(name: "Other", kind: .wallet, dataSource: .zerion)
        other.addresses = [WalletAddress(address: "0xother", account: other)]
        other.positions = [stalePosition]
        context.insert(staleAsset)
        context.insert(selected)
        context.insert(other)
        try context.save()

        let result = try await engine.sync(accountID: selected.id)

        #expect(resolvedAccountIDs.withLock { $0 } == [selected.id])
        #expect(selected.lastSyncedAt != nil)
        #expect(other.lastSyncedAt == nil)
        #expect(result.failedAccounts.isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 2)
        let accountSnapshots = try context.fetch(FetchDescriptor<AccountSnapshot>())
        let selectedSnapshot = try #require(accountSnapshots.first { $0.accountId == selected.id })
        let otherSnapshot = try #require(accountSnapshots.first { $0.accountId == other.id })
        #expect(selectedSnapshot.isFresh == true)
        #expect(otherSnapshot.isFresh == false)
        let portfolioSnapshot = try #require(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).first)
        #expect(portfolioSnapshot.isPartial == true)
        let assetSnapshots = try context.fetch(FetchDescriptor<AssetSnapshot>())
        #expect(assetSnapshots.allSatisfy { $0.accountId == selected.id })
    }

    @Test func `partial sync asset snapshots skip failed account stale positions`() async throws {
        let context = try makeModelContext()
        let provider = ScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let succeeded = Account(name: "Succeeded", kind: .wallet, dataSource: .zerion)
        succeeded.addresses = [WalletAddress(address: "0xsucceeded", account: succeeded)]
        let staleAsset = Asset(symbol: "OLD", name: "Old Token", category: .major)
        let staleToken = PositionToken(role: .balance, amount: 1, usdValue: 100, asset: staleAsset)
        let stalePosition = Position(positionType: .idle, chain: .ethereum, netUSDValue: 100, tokens: [staleToken])
        let failed = Account(name: "Failed", kind: .wallet, dataSource: .zerion)
        failed.addresses = [WalletAddress(address: "0xfailed", account: failed)]
        failed.positions = [stalePosition]
        let failedID = failed.id
        let factory = ProviderFactory(resolver: { _, context in
            if context.accountId == failedID {
                throw SyncEngineScopedTestError.forcedProviderFailure
            }
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        context.insert(staleAsset)
        context.insert(succeeded)
        context.insert(failed)
        try context.save()

        let result = try await engine.sync()

        #expect(result.failedAccounts == ["Failed"])
        let assetSnapshots = try context.fetch(FetchDescriptor<AssetSnapshot>())
        #expect(assetSnapshots.allSatisfy { $0.accountId == succeeded.id })
        let failedSnapshot = try #require(try context.fetch(FetchDescriptor<AccountSnapshot>()).first { $0.accountId == failed.id })
        #expect(failedSnapshot.isFresh == false)
    }

    @Test func `account scoped sync snapshot is complete when selected account is the only syncable account`() async throws {
        let context = try makeModelContext()
        let provider = ScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let factory = ProviderFactory(resolver: { _, _ in provider })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zerion)
        selected.addresses = [WalletAddress(address: "0xselected", account: selected)]
        let manual = Account(name: "Manual", kind: .manual, dataSource: .manual)
        context.insert(selected)
        context.insert(manual)
        try context.save()

        _ = try await engine.sync(accountID: selected.id)

        let portfolioSnapshot = try #require(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).first)
        #expect(portfolioSnapshot.isPartial == false)
    }

    @Test func `account scoped sync recomputes snapshot partial state after provider awaits`() async throws {
        let context = try makeModelContext()
        let provider = GatedScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let factory = ProviderFactory(resolver: { _, _ in provider })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zerion)
        selected.addresses = [WalletAddress(address: "0xselected", account: selected)]
        let other = Account(name: "Other", kind: .wallet, dataSource: .zerion, isActive: false)
        other.addresses = [WalletAddress(address: "0xother", account: other)]
        context.insert(selected)
        context.insert(other)
        try context.save()

        let syncTask = Task {
            try await engine.sync(accountID: selected.id)
        }
        await provider.waitUntilFetchBalancesStarted()
        other.isActive = true
        try context.save()
        await provider.releaseFetchBalances()

        _ = try await syncTask.value

        let portfolioSnapshot = try #require(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).first)
        #expect(portfolioSnapshot.isPartial == true)
    }

    @Test func `account scoped sync stays partial when selected account is deactivated before snapshots`() async throws {
        let context = try makeModelContext()
        let provider = GatedScopedSyncStubProvider(balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")])
        ])
        let factory = ProviderFactory(resolver: { _, _ in provider })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zerion)
        selected.addresses = [WalletAddress(address: "0xselected", account: selected)]
        let other = Account(name: "Other", kind: .wallet, dataSource: .zerion)
        other.addresses = [WalletAddress(address: "0xother", account: other)]
        context.insert(selected)
        context.insert(other)
        try context.save()

        let syncTask = Task {
            try await engine.sync(accountID: selected.id)
        }
        await provider.waitUntilFetchBalancesStarted()
        selected.isActive = false
        try context.save()
        await provider.releaseFetchBalances()

        _ = try await syncTask.value

        let portfolioSnapshot = try #require(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).first)
        #expect(portfolioSnapshot.isPartial == true)
        let accountSnapshot = try #require(try context.fetch(FetchDescriptor<AccountSnapshot>()).first)
        #expect(accountSnapshot.accountId == other.id)
        #expect(accountSnapshot.isFresh == false)
    }

    @Test func `account scoped sync rejects missing account`() async throws {
        let context = try makeModelContext()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in ScopedSyncStubProvider(balances: []) }))

        do {
            _ = try await engine.sync(accountID: UUID())
            Issue.record("Expected missing account sync to throw.")
        } catch SyncError.accountNotFound {
            // Expected.
        } catch {
            Issue.record("Expected accountNotFound, got \(error).")
        }
    }

    @Test func `account scoped sync rejects manual account`() async throws {
        let context = try makeModelContext()
        let manual = Account(name: "Manual", kind: .manual, dataSource: .manual)
        context.insert(manual)
        try context.save()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in ScopedSyncStubProvider(balances: []) }))

        do {
            _ = try await engine.sync(accountID: manual.id)
            Issue.record("Expected manual account sync to throw.")
        } catch SyncError.accountNotSyncable {
            // Expected.
        } catch {
            Issue.record("Expected accountNotSyncable, got \(error).")
        }
    }

    @Test func `account scoped sync rejects inactive account`() async throws {
        let context = try makeModelContext()
        let inactive = Account(name: "Inactive", kind: .wallet, dataSource: .zerion, isActive: false)
        context.insert(inactive)
        try context.save()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in ScopedSyncStubProvider(balances: []) }))

        do {
            _ = try await engine.sync(accountID: inactive.id)
            Issue.record("Expected inactive account sync to throw.")
        } catch SyncError.accountInactive {
            // Expected.
        } catch {
            Issue.record("Expected accountInactive, got \(error).")
        }
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self, TokenPricingOverride.self,
            TokenIdentityMapping.self,
            HistoricalPricePoint.self,
            PortfolioCategory.self, CategorySymbolRule.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
            ProviderPortfolioValuePoint.self, ProviderPortfolioHistoryRefresh.self,
            ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTokenDTO(
        symbol: String,
        name: String,
        coinGeckoId: String?) -> TokenDTO {
        TokenDTO(
            role: .balance,
            symbol: symbol,
            name: name,
            amount: 100,
            usdValue: 100,
            chain: nil,
            contractAddress: nil,
            debankId: nil,
            coinGeckoId: coinGeckoId,
            sourceKey: nil,
            logoURL: nil,
            category: .other,
            isVerified: false)
    }
}

private actor ScopedSyncStubProvider: PortfolioDataProvider {
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

private actor GatedScopedSyncStubProvider: PortfolioDataProvider {
    nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities()
    }

    let balances: [PositionDTO]
    private var didStartFetchBalances = false
    private var didReleaseFetchBalances = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(balances: [PositionDTO]) {
        self.balances = balances
    }

    func waitUntilFetchBalancesStarted() async {
        if didStartFetchBalances {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseFetchBalances() {
        didReleaseFetchBalances = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        didStartFetchBalances = true
        startContinuation?.resume()
        startContinuation = nil

        if didReleaseFetchBalances == false {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        return balances
    }
}

private enum SyncEngineScopedTestError: Error {
    case forcedProviderFailure
}
