import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct AccountSheetInvalidationTests {
    @Test func `wallet edit clears synced positions when wallet identity changes`() async throws {
        let context = try makeModelContext()
        let account = Account(
            name: "Wallet",
            kind: .wallet,
            dataSource: .zerion,
            lastSyncedAt: Date(timeIntervalSince1970: 1000),
            lastSyncError: "old failure")
        context.insert(account)
        let address = WalletAddress(chain: nil, address: "0xold", account: account)
        context.insert(address)
        account.addresses = [address]
        insertSyncedPosition(for: account, in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)

        var draft = AccountSheetDraft.editing(account: account)
        draft.chainAddress = "0xnew"

        try await AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(account.id),
            editing: account,
            modelContext: context,
            secretStore: InMemorySecretStore())

        let updated = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        #expect(updated.positions.isEmpty)
        #expect(updated.lastSyncedAt == nil)
        #expect(updated.lastSyncError == nil)
        #expect(try context.fetch(FetchDescriptor<Position>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PositionToken>()).isEmpty)
    }

    @Test func `exchange edit clears synced positions when credentials change`() async throws {
        let context = try makeModelContext()
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "old-key"
        store.storage[.exchangeAPISecret(accountID)] = "old-secret"
        store.storage[.exchangePassphrase(accountID)] = "old-passphrase"
        let account = Account(
            id: accountID,
            name: "Coinbase",
            kind: .exchange,
            exchangeType: .coinbase,
            dataSource: .exchange,
            lastSyncedAt: Date(timeIntervalSince1970: 1000),
            lastSyncError: "old failure")
        context.insert(account)
        insertSyncedPosition(for: account, in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)

        var draft = await AccountSheetDraft.editing(account: account, secretStore: store)
        draft.exchangeAPIKey = "new-key"

        try await AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(accountID),
            editing: account,
            modelContext: context,
            secretStore: store)

        let updated = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        #expect(updated.positions.isEmpty)
        #expect(updated.lastSyncedAt == nil)
        #expect(updated.lastSyncError == nil)
        #expect(store.storage[.exchangeAPIKey(accountID)] == "new-key")
        #expect(try context.fetch(FetchDescriptor<Position>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PositionToken>()).isEmpty)
    }

    @Test func `exchange credential reads and writes run off the main actor`() async throws {
        let context = try makeModelContext()
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "old-key"
        store.storage[.exchangeAPISecret(accountID)] = "old-secret"
        let account = Account(
            id: accountID,
            name: "Kraken",
            kind: .exchange,
            exchangeType: .kraken,
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account)
        await draft.loadExchangeCredentials(accountID: accountID, secretStore: store)
        draft.exchangeAPIKey = "new-key"
        draft.exchangeAPISecret = "new-secret"
        try await AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(accountID),
            editing: account,
            modelContext: context,
            secretStore: store)

        #expect(!store.mainThreadFlags.isEmpty)
        #expect(store.mainThreadFlags.allSatisfy { !$0 })
    }

    @Test func `retained Zapper wallet identity cannot be edited destructively`() async throws {
        let context = try makeModelContext()
        let account = Account(name: "Legacy", kind: .wallet, dataSource: .zapper)
        let address = WalletAddress(chain: .bitcoin, address: "old-address", account: account)
        account.addresses = [address]
        context.insert(account)
        context.insert(address)
        insertSyncedPosition(for: account, in: context)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account)
        draft.isEVM = true
        draft.chainAddress = "0xnew"

        await #expect(throws: AccountSheetSaveError.self) {
            try await AccountSheetSaveCoordinator.save(
                draft: draft,
                mode: .edit(account.id),
                editing: account,
                modelContext: context,
                secretStore: InMemorySecretStore())
        }

        #expect(account.addresses.map(\.address) == ["old-address"])
        #expect(account.positions.count == 1)
    }

    @Test func `wallet identity edit removes obsolete provider analytics`() async throws {
        let context = try makeModelContext()
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        let address = WalletAddress(
            chain: nil,
            address: "0x1111111111111111111111111111111111111111",
            account: account)
        account.addresses = [address]
        context.insert(account)
        context.insert(address)
        insertAnalytics(for: account.id, in: context)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account)
        draft.chainAddress = "0x2222222222222222222222222222222222222222"
        try await AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(account.id),
            editing: account,
            modelContext: context,
            secretStore: InMemorySecretStore())

        #expect(try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProviderPnLSnapshot>()).isEmpty)
    }

    @Test func `wallet chain edit removes obsolete provider analytics`() async throws {
        let context = try makeModelContext()
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        let address = WalletAddress(
            chain: .polygon,
            address: "0x1111111111111111111111111111111111111111",
            account: account)
        account.addresses = [address]
        context.insert(account)
        context.insert(address)
        insertAnalytics(for: account.id, in: context)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account)
        draft.isEVM = false
        draft.specificChain = .ethereum
        try await AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(account.id),
            editing: account,
            modelContext: context,
            secretStore: InMemorySecretStore())

        #expect(account.addresses.map(\.chain) == [.ethereum])
        #expect(try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProviderPnLSnapshot>()).isEmpty)
    }

    @Test func `account deletion removes provider analytics`() async throws {
        let context = try makeModelContext()
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        insertAnalytics(for: account.id, in: context)
        try context.save()

        try await AccountSheetSaveCoordinator.deleteAccount(
            account,
            modelContext: context,
            secretStore: InMemorySecretStore())

        #expect(try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProviderPnLSnapshot>()).isEmpty)
    }

    @Test func `deactivation preserves cached analytics`() throws {
        let context = try makeModelContext()
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        insertAnalytics(for: account.id, in: context)
        try context.save()

        try AccountSheetSaveCoordinator.setAccount(
            account,
            isActive: false,
            modelContext: context)

        #expect(try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProviderPnLSnapshot>()).count == 1)
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            TokenPricingOverride.self,
            TokenIdentityMapping.self,
            HistoricalPricePoint.self,
            PortfolioCategory.self,
            CategorySymbolRule.self,
            PortfolioSnapshot.self,
            AccountSnapshot.self,
            AssetSnapshot.self,
            ProviderPortfolioValuePoint.self,
            ProviderPortfolioHistoryRefresh.self,
            ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func insertSyncedPosition(for account: Account, in context: ModelContext) {
        let position = Position(
            positionType: .idle,
            netUSDValue: 100,
            syncedAt: Date(timeIntervalSince1970: 900))
        context.insert(position)
        position.account = account
        let token = PositionToken(role: .balance, amount: 1, usdValue: 100)
        context.insert(token)
        token.position = position
    }

    private func insertAnalytics(for accountID: UUID, in context: ModelContext) {
        context.insert(ProviderPortfolioValuePoint(
            accountID: accountID,
            scopeFingerprint: "old-scope",
            provider: .zerion,
            coverage: .providerReported,
            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
            usdValue: 100))
        context.insert(ProviderPnLSnapshot(
            accountID: accountID,
            scopeFingerprint: "old-scope",
            provider: .zerion,
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: Date(timeIntervalSince1970: 1_704_067_200)))
    }
}
