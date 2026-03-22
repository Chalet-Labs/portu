import Foundation
import Testing
@testable import PortuCore

actor MockSecretStore: SecretStore {
    private var storage: [KeychainKey: String] = [:]

    func value(for key: KeychainKey) async throws(KeychainError) -> String? {
        return storage[key]
    }

    func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError) {
        storage[key] = value
    }

    func removeValue(for key: KeychainKey) async throws(KeychainError) {
        storage[key] = nil
    }
}

@Suite("SecretStore Tests")
struct SecretStoreTests {
    @Test func storeAndRetrieve() async throws {
        let store = MockSecretStore()
        let key = KeychainKey.exchangeAPIKey(UUID())

        try await store.setValue("my-secret-key", for: key)
        let retrieved = try await store.value(for: key)

        #expect(retrieved == "my-secret-key")
    }

    @Test func retrieveNonExistent() async throws {
        let store = MockSecretStore()
        let result = try await store.value(for: .exchangeAPISecret(UUID()))

        #expect(result == nil)
    }

    @Test func deleteKey() async throws {
        let store = MockSecretStore()
        let key = KeychainKey.exchangePassphrase(UUID())

        try await store.setValue("secret", for: key)
        try await store.removeValue(for: key)
        let result = try await store.value(for: key)

        #expect(result == nil)
    }

    @Test func overwriteExistingKey() async throws {
        let store = MockSecretStore()
        let key = KeychainKey.exchangeAPIKey(UUID())

        try await store.setValue("old", for: key)
        try await store.setValue("new", for: key)
        let result = try await store.value(for: key)

        #expect(result == "new")
    }

    @Test func keychainKeysUseStableServicePrefixes() {
        #expect(KeychainKey.providerAPIKey(.zapper).service == "portu.provider.zapper.apiKey")
    }
}
