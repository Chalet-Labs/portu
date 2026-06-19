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

    @Test func `partial exchange credential load does not mutate draft fields`() {
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "stored-key"
        store.storage[.exchangeAPISecret(accountID)] = "stored-secret"
        store.throwOnGetKeys = [.exchangePassphrase(accountID)]
        var draft = AccountSheetDraft()
        draft.exchangeAPIKey = "typed-key"
        draft.exchangeAPISecret = "typed-secret"
        draft.exchangePassphrase = "typed-passphrase"

        draft.loadExchangeCredentials(accountID: accountID, secretStore: store)

        #expect(draft.exchangeCredentialsLoaded == false)
        #expect(draft.exchangeAPIKey == "typed-key")
        #expect(draft.exchangeAPISecret == "typed-secret")
        #expect(draft.exchangePassphrase == "typed-passphrase")
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
            secretStore: InMemorySecretStore())

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let updated = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(updated.id == account.id)
        #expect(updated.name == "Manual Updated")
        #expect(updated.group == "New")
        #expect(updated.notes == "After")
    }

    @Test func `exchange edit credential save failure leaves the account unmutated`() throws {
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
            dataSource: .exchange,
            group: "CEX")
        context.insert(account)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account, secretStore: store)
        draft.exchangeName = "Renamed"
        draft.exchangeAPIKey = "new-key"
        draft.exchangeAPISecret = "new-secret"
        store.throwOnSet = true

        #expect(throws: AccountSheetSaveError.self) {
            try AccountSheetSaveCoordinator.save(
                draft: draft,
                mode: .edit(accountID),
                editing: account,
                modelContext: context,
                secretStore: store)
        }

        // Credentials are written before the model is mutated, so a keychain failure
        // leaves the account name untouched (nothing for autosave to flush).
        let reloaded = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        #expect(reloaded.name == "Kraken")
    }

    @Test func `exchange edit credential write failure restores previous credentials`() throws {
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
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account, secretStore: store)
        draft.exchangeName = "Coinbase Prime"
        draft.exchangeAPIKey = "new-key"
        draft.exchangeAPISecret = "new-secret"
        draft.exchangePassphrase = "new-passphrase"
        store.throwOnSetKeys = [.exchangeAPISecret(accountID)]

        #expect(throws: AccountSheetSaveError.self) {
            try AccountSheetSaveCoordinator.save(
                draft: draft,
                mode: .edit(accountID),
                editing: account,
                modelContext: context,
                secretStore: store)
        }

        #expect(store.storage[.exchangeAPIKey(accountID)] == "old-key")
        #expect(store.storage[.exchangeAPISecret(accountID)] == "old-secret")
        #expect(store.storage[.exchangePassphrase(accountID)] == "old-passphrase")
    }

    @Test func `exchange edit with a failed credential read preserves the stored passphrase`() throws {
        let context = try makeModelContext()
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "real-key"
        store.storage[.exchangeAPISecret(accountID)] = "real-secret"
        store.storage[.exchangePassphrase(accountID)] = "real-passphrase"
        let account = Account(
            id: accountID,
            name: "Coinbase",
            kind: .exchange,
            exchangeType: .coinbase,
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        store.throwOnGet = true
        var draft = AccountSheetDraft.editing(account: account, secretStore: store)
        #expect(draft.exchangeCredentialsLoaded == false)

        // User supplies fresh required fields but leaves the passphrase blank.
        draft.exchangeAPIKey = "typed-key"
        draft.exchangeAPISecret = "typed-secret"
        store.throwOnGet = false

        try AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(accountID),
            editing: account,
            modelContext: context,
            secretStore: store)

        // The blank passphrase must not be mistaken for "cleared" — it was never loaded.
        #expect(store.storage[.exchangePassphrase(accountID)] == "real-passphrase")
        #expect(store.storage[.exchangeAPIKey(accountID)] == "typed-key")
    }

    @Test func `wallet edit replaces all addresses with a single row`() throws {
        let context = try makeModelContext()
        let account = Account(name: "Multi", kind: .wallet, dataSource: .zapper)
        account.addresses = [
            WalletAddress(chain: nil, address: "0xaaa", account: account),
            WalletAddress(chain: .solana, address: "sol111", account: account)
        ]
        context.insert(account)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<WalletAddress>()).count == 2)

        var draft = AccountSheetDraft.editing(account: account)
        draft.isEVM = true
        draft.chainAddress = "0xnew"

        try AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(account.id),
            editing: account,
            modelContext: context,
            secretStore: InMemorySecretStore())

        let addresses = try context.fetch(FetchDescriptor<WalletAddress>())
        #expect(addresses.count == 1)
        #expect(addresses.first?.address == "0xnew")
        #expect(addresses.first?.chain == nil)
    }

    @Test func `wallet add persists a managed address row`() throws {
        let context = try makeModelContext()
        var draft = AccountSheetDraft.adding()
        draft.selectedTab = .chain
        draft.chainName = "Wallet"
        draft.chainAddress = "0xabc"
        draft.isEVM = false
        draft.specificChain = .base

        try AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .add,
            editing: nil,
            modelContext: context,
            secretStore: InMemorySecretStore())

        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        let address = try #require(try context.fetch(FetchDescriptor<WalletAddress>()).first)
        #expect(account.addresses.map(\.id) == [address.id])
        #expect(address.account?.id == account.id)
        #expect(address.chain == .base)
        #expect(address.address == "0xabc")
    }

    @Test func `delete exchange account removes credentials after successful save`() throws {
        let context = try makeModelContext()
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "key"
        store.storage[.exchangeAPISecret(accountID)] = "secret"
        store.storage[.exchangePassphrase(accountID)] = "passphrase"
        let account = Account(
            id: accountID,
            name: "Kraken",
            kind: .exchange,
            exchangeType: .kraken,
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        try AccountSheetSaveCoordinator.deleteAccount(account, modelContext: context, secretStore: store)

        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(store.storage[.exchangeAPIKey(accountID)] == nil)
        #expect(store.storage[.exchangeAPISecret(accountID)] == nil)
        #expect(store.storage[.exchangePassphrase(accountID)] == nil)
    }

    @Test func `delete exchange account keeps credentials when save fails`() throws {
        let context = try makeModelContext()
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "key"
        store.storage[.exchangeAPISecret(accountID)] = "secret"
        let account = Account(
            id: accountID,
            name: "Kraken",
            kind: .exchange,
            exchangeType: .kraken,
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        #expect(throws: AccountSheetSaveError.self) {
            try AccountSheetSaveCoordinator.deleteAccount(
                account,
                modelContext: context,
                secretStore: store,
                save: { _ in throw KeychainError.interactionNotAllowed })
        }

        #expect(store.storage[.exchangeAPIKey(accountID)] == "key")
        #expect(store.storage[.exchangeAPISecret(accountID)] == "secret")
        #expect(try context.fetch(FetchDescriptor<Account>()).count == 1)
    }

    @Test func `delete exchange account keeps account and credentials when credential deletion fails`() throws {
        let context = try makeModelContext()
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "key"
        store.storage[.exchangeAPISecret(accountID)] = "secret"
        store.storage[.exchangePassphrase(accountID)] = "passphrase"
        store.throwOnDeleteKeys = [.exchangeAPISecret(accountID)]
        let account = Account(
            id: accountID,
            name: "Kraken",
            kind: .exchange,
            exchangeType: .kraken,
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        #expect(throws: AccountSheetSaveError.self) {
            try AccountSheetSaveCoordinator.deleteAccount(account, modelContext: context, secretStore: store)
        }

        #expect(store.storage[.exchangeAPIKey(accountID)] == "key")
        #expect(store.storage[.exchangeAPISecret(accountID)] == "secret")
        #expect(store.storage[.exchangePassphrase(accountID)] == "passphrase")
        #expect(try context.fetch(FetchDescriptor<Account>()).count == 1)
    }

    @Test func `set account active saves the account state`() throws {
        let context = try makeModelContext()
        let account = Account(name: "Archived", kind: .wallet, dataSource: .zapper, isActive: false)
        context.insert(account)
        try context.save()

        try AccountSheetSaveCoordinator.setAccount(account, isActive: true, modelContext: context)

        let reloaded = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        #expect(reloaded.isActive == true)
    }

    @Test func `set account active rolls back when save fails`() throws {
        let context = try makeModelContext()
        let account = Account(name: "Active", kind: .wallet, dataSource: .zapper, isActive: true)
        context.insert(account)
        try context.save()

        #expect(throws: AccountSheetSaveError.self) {
            try AccountSheetSaveCoordinator.setAccount(
                account,
                isActive: false,
                modelContext: context,
                save: { _ in throw KeychainError.interactionNotAllowed })
        }

        let reloaded = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        #expect(reloaded.isActive == true)
    }

    @Test func `editing a deleted account throws missingEditedAccount`() throws {
        let context = try makeModelContext()
        let account = Account(name: "Doomed", kind: .manual, dataSource: .manual)
        context.insert(account)
        try context.save()
        let id = account.id
        let draft = AccountSheetDraft.editing(account: account)

        context.delete(account)
        try context.save()

        #expect(throws: AccountSheetSaveError.missingEditedAccount) {
            try AccountSheetSaveCoordinator.save(
                draft: draft,
                mode: .edit(id),
                editing: account,
                modelContext: context,
                secretStore: InMemorySecretStore())
        }
    }

    @Test func `whitespace-only group and notes persist as nil`() throws {
        let context = try makeModelContext()
        let account = Account(name: "M", kind: .manual, dataSource: .manual, group: "x", notes: "y")
        context.insert(account)
        try context.save()

        var draft = AccountSheetDraft.editing(account: account)
        draft.manualGroup = "   "
        draft.manualNotes = "\n\t "

        try AccountSheetSaveCoordinator.save(
            draft: draft,
            mode: .edit(account.id),
            editing: account,
            modelContext: context,
            secretStore: InMemorySecretStore())

        let updated = try #require(try context.fetch(FetchDescriptor<Account>()).first)
        #expect(updated.group == nil)
        #expect(updated.notes == nil)
    }

    @Test func `deleting exchange credentials removes all stored keys`() throws {
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "k"
        store.storage[.exchangeAPISecret(accountID)] = "s"
        store.storage[.exchangePassphrase(accountID)] = "p"

        try AccountSheetSaveCoordinator.deleteExchangeCredentials(accountID, secretStore: store)

        #expect(store.storage[.exchangeAPIKey(accountID)] == nil)
        #expect(store.storage[.exchangeAPISecret(accountID)] == nil)
        #expect(store.storage[.exchangePassphrase(accountID)] == nil)
    }

    @Test func `save policy blocks submit while syncing`() {
        #expect(AddAccountSheetSavePolicy.canSubmit(draftCanSave: true, isSyncing: false, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canSubmit(draftCanSave: false, isSyncing: false, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canSubmit(draftCanSave: true, isSyncing: true, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canSubmit(draftCanSave: true, isSyncing: false, isSyncBlocked: true))
    }

    @Test func `save policy blocks field editing while syncing`() {
        #expect(AddAccountSheetSavePolicy.canEditFields(isSyncing: false, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(isSyncing: true, isSyncBlocked: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(isSyncing: false, isSyncBlocked: true))
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

/// In-memory `SecretStore` test double with configurable failure injection.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    var storage: [KeychainKey: String] = [:]
    var throwOnGet = false
    var throwOnGetKeys: Set<KeychainKey> = []
    var throwOnSet = false
    var throwOnSetKeys: Set<KeychainKey> = []
    var throwOnDeleteKeys: Set<KeychainKey> = []

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        if throwOnGet || throwOnGetKeys.contains(key) { throw .interactionNotAllowed }
        return storage[key]
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        if throwOnSet || throwOnSetKeys.contains(key) { throw .interactionNotAllowed }
        storage[key] = value
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        if throwOnDeleteKeys.contains(key) { throw .interactionNotAllowed }
        storage[key] = nil
    }
}
