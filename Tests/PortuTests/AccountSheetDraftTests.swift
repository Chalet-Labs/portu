import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct AccountSheetDraftTests {
    @Test func `wallet edit draft pre-fills account data and chain`() {
        let account = Account(
            name: "Hardware Wallet",
            kind: .wallet,
            dataSource: .zapper,
            group: "Cold",
            notes: "Long-term storage")
        account.addresses = [WalletAddress(chain: .solana, address: "So11111111111111111111111111111111111111112", account: account)]

        let draft = AccountSheetDraft.editing(account: account)

        #expect(draft.selectedTab == .chain)
        #expect(draft.chainName == "Hardware Wallet")
        #expect(draft.chainAddress == "So11111111111111111111111111111111111111112")
        #expect(draft.chainGroup == "Cold")
        #expect(draft.chainNotes == "Long-term storage")
        #expect(draft.isEVM == false)
        #expect(draft.specificChain == .solana)
    }

    @Test func `exchange edit draft pre-fills saved credentials`() throws {
        let suiteName = "AccountSheetDraftTests-\(UUID().uuidString)"
        let store = LocalSecretStore(suiteName: suiteName)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let accountID = UUID()
        try store.set(key: .exchangeAPIKey(accountID), value: "api-key")
        try store.set(key: .exchangeAPISecret(accountID), value: "api-secret")
        try store.set(key: .exchangePassphrase(accountID), value: "passphrase")
        let account = Account(
            id: accountID,
            name: "Coinbase",
            kind: .exchange,
            exchangeType: .coinbase,
            dataSource: .exchange,
            group: "CEX",
            notes: "Read-only")

        let draft = AccountSheetDraft.editing(account: account, secretStore: store)

        #expect(draft.selectedTab == .exchange)
        #expect(draft.exchangeName == "Coinbase")
        #expect(draft.exchangeType == .coinbase)
        #expect(draft.exchangeAPIKey == "api-key")
        #expect(draft.exchangeAPISecret == "api-secret")
        #expect(draft.exchangePassphrase == "passphrase")
        #expect(draft.exchangeGroup == "CEX")
        #expect(draft.exchangeNotes == "Read-only")
    }

    @Test func `saving edit mode mutates existing account instead of inserting`() throws {
        let context = try makeModelContext()
        let account = Account(
            name: "Manual",
            kind: .manual,
            dataSource: .manual,
            group: "Old",
            notes: "Before")
        context.insert(account)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account)
        draft.manualName = "Manual Updated"
        draft.manualGroup = "New"
        draft.manualNotes = "After"

        try AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(account.id),
            editing: account,
            modelContext: context,
            secretStore: LocalSecretStore(suiteName: "AccountSheetDraftTests-\(UUID().uuidString)"))

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let updated = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(updated.id == account.id)
        #expect(updated.name == "Manual Updated")
        #expect(updated.group == "New")
        #expect(updated.notes == "After")
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
}
