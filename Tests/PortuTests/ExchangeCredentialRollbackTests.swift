import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

private final class SequencedCredentialSecretStore: SecretStore, @unchecked Sendable {
    var storage: [KeychainKey: String] = [:]
    var setErrors: [KeychainKey: [Int: KeychainError]] = [:]
    private var setCounts: [KeychainKey: Int] = [:]

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        storage[key]
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        let count = setCounts[key, default: 0] + 1
        setCounts[key] = count
        if let error = setErrors[key]?[count] {
            throw error
        }
        storage[key] = value
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        storage[key] = nil
    }
}

struct ExchangeCredentialRollbackTests {
    @Test func `save surfaces rollback failure after a later credential write fails`() async throws {
        let accountID = UUID()
        let apiKey = KeychainKey.exchangeAPIKey(accountID)
        let apiSecret = KeychainKey.exchangeAPISecret(accountID)
        let passphrase = KeychainKey.exchangePassphrase(accountID)
        let store = SequencedCredentialSecretStore()
        store.storage = [
            apiKey: "old-key",
            apiSecret: "old-secret",
            passphrase: "old-passphrase"
        ]
        store.setErrors = [
            apiKey: [2: .interactionNotAllowed],
            apiSecret: [1: .unexpectedStatus(-1)]
        ]
        let credentials = ExchangeCredentialSnapshot(
            apiKey: "new-key",
            apiSecret: "new-secret",
            passphrase: "new-passphrase")
        let previous = ExchangeCredentialSnapshot(
            apiKey: "old-key",
            apiSecret: "old-secret",
            passphrase: "old-passphrase")
        let credentialStore = AccountCredentialStore(secretStore: store)

        await #expect(throws: KeychainError.interactionNotAllowed) {
            try await credentialStore.save(
                credentials,
                for: accountID,
                rollbackTo: previous)
        }
        #expect(store.storage[apiSecret] == "old-secret")
        #expect(store.storage[passphrase] == "old-passphrase")
    }

    @MainActor
    @Test func `account save rollback surfaces credential restore failure`() async throws {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self, TokenPricingOverride.self,
            TokenIdentityMapping.self, HistoricalPricePoint.self,
            PortfolioCategory.self, CategorySymbolRule.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
            ProviderPortfolioValuePoint.self, ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let accountID = UUID()
        let apiKey = KeychainKey.exchangeAPIKey(accountID)
        let apiSecret = KeychainKey.exchangeAPISecret(accountID)
        let store = SequencedCredentialSecretStore()
        store.storage = [apiKey: "key", apiSecret: "secret"]
        store.setErrors = [apiKey: [1: .interactionNotAllowed]]
        let account = Account(
            id: accountID,
            name: "Kraken",
            kind: .exchange,
            exchangeType: .kraken,
            dataSource: .exchange)
        context.insert(account)
        try context.save()

        await #expect(throws: AccountSheetSaveError.credentialSaveFailed(
            KeychainError.interactionNotAllowed.localizedDescription)) {
            try await AccountSheetSaveCoordinator.deleteAccount(
                account,
                modelContext: context,
                secretStore: store,
                save: { _ in throw KeychainError.unexpectedStatus(-1) })
        }
        #expect(try context.fetch(FetchDescriptor<Account>()).count == 1)
    }
}
