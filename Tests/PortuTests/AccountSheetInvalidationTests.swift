import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct AccountSheetInvalidationTests {
    @Test func `wallet edit clears synced positions when wallet identity changes`() throws {
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

        try AccountSheetSaveCoordinator.save(
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

    @Test func `exchange edit clears synced positions when credentials change`() throws {
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

        var draft = AccountSheetDraft.editing(account: account, secretStore: store)
        draft.exchangeAPIKey = "new-key"

        try AccountSheetSaveCoordinator.save(
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
            AssetSnapshot.self
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
}
