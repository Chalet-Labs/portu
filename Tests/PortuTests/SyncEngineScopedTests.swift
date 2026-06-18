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
