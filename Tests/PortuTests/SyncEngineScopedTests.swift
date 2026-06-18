import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

@MainActor
struct SyncEngineScopedTests {
    @Test func `scoped zapper sync fetches only zapper accounts`() async throws {
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
        nonisolated(unsafe) var resolvedSources: [DataSource] = []
        let factory = ProviderFactory(resolver: { dataSource, _ in
            resolvedSources.append(dataSource)
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let wallet = Account(name: "Wallet", kind: .wallet, dataSource: .zapper)
        let exchange = Account(name: "Kraken", kind: .exchange, exchangeType: .kraken, dataSource: .exchange)
        context.insert(wallet)
        context.insert(exchange)
        try context.save()

        let result = try await engine.sync(scope: .zapper)

        #expect(resolvedSources == [.zapper])
        #expect(wallet.lastSyncedAt != nil)
        #expect(exchange.lastSyncedAt == nil)
        #expect(result.failedAccounts.isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 2)
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
        nonisolated(unsafe) var resolvedSources: [DataSource] = []
        let factory = ProviderFactory(resolver: { dataSource, _ in
            resolvedSources.append(dataSource)
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let wallet = Account(name: "Wallet", kind: .wallet, dataSource: .zapper)
        let exchange = Account(name: "Kraken", kind: .exchange, exchangeType: .kraken, dataSource: .exchange)
        context.insert(wallet)
        context.insert(exchange)
        try context.save()

        let result = try await engine.sync(scope: .exchange)

        #expect(resolvedSources == [.exchange])
        #expect(wallet.lastSyncedAt == nil)
        #expect(exchange.lastSyncedAt != nil)
        #expect(result.failedAccounts.isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 2)
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
        nonisolated(unsafe) var resolvedAccountIDs: [UUID] = []
        let factory = ProviderFactory(resolver: { _, context in
            resolvedAccountIDs.append(context.accountId)
            return provider
        })
        let engine = SyncEngine(modelContext: context, providerFactory: factory)
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zapper)
        selected.addresses = [WalletAddress(address: "0xselected", account: selected)]
        let other = Account(name: "Other", kind: .wallet, dataSource: .zapper)
        other.addresses = [WalletAddress(address: "0xother", account: other)]
        context.insert(selected)
        context.insert(other)
        try context.save()

        let result = try await engine.sync(accountID: selected.id)

        #expect(resolvedAccountIDs == [selected.id])
        #expect(selected.lastSyncedAt != nil)
        #expect(other.lastSyncedAt == nil)
        #expect(result.failedAccounts.isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 2)
        let portfolioSnapshot = try #require(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).first)
        #expect(portfolioSnapshot.isPartial == true)
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
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zapper)
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
        let selected = Account(name: "Selected", kind: .wallet, dataSource: .zapper)
        selected.addresses = [WalletAddress(address: "0xselected", account: selected)]
        let other = Account(name: "Other", kind: .wallet, dataSource: .zapper, isActive: false)
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
        let inactive = Account(name: "Inactive", kind: .wallet, dataSource: .zapper, isActive: false)
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
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
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
        if didStartFetchBalances { return }

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
