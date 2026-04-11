import Foundation
@testable import PortuCore
import Testing

/// In-memory mock for testing code that depends on SecretStore.
final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        storage[key.rawKey]
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        storage[key.rawKey] = value
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        storage.removeValue(forKey: key.rawKey)
    }
}

struct SecretStoreTests {
    @Test func `store and retrieve`() throws {
        let store = MockSecretStore()
        let id = UUID()
        try store.set(key: .exchangeAPIKey(id), value: "my-secret-key")
        let retrieved = try store.get(key: .exchangeAPIKey(id))
        #expect(retrieved == "my-secret-key")
    }

    @Test func `retrieve non existent`() throws {
        let store = MockSecretStore()
        let result = try store.get(key: .providerAPIKey(.zapper))
        #expect(result == nil)
    }

    @Test func `delete key`() throws {
        let store = MockSecretStore()
        let id = UUID()
        try store.set(key: .exchangeAPIKey(id), value: "secret")
        try store.delete(key: .exchangeAPIKey(id))
        let result = try store.get(key: .exchangeAPIKey(id))
        #expect(result == nil)
    }

    @Test func `overwrite existing key`() throws {
        let store = MockSecretStore()
        let id = UUID()
        try store.set(key: .exchangeAPIKey(id), value: "old")
        try store.set(key: .exchangeAPIKey(id), value: "new")
        let result = try store.get(key: .exchangeAPIKey(id))
        #expect(result == "new")
    }

    @Test func `different key types are independent`() throws {
        let store = MockSecretStore()
        let id = UUID()
        try store.set(key: .exchangeAPIKey(id), value: "key-value")
        try store.set(key: .exchangeAPISecret(id), value: "secret-value")
        #expect(try store.get(key: .exchangeAPIKey(id)) == "key-value")
        #expect(try store.get(key: .exchangeAPISecret(id)) == "secret-value")
    }

    @Test func `rawKey format is stable`() {
        let id = UUID()
        #expect(KeychainKey.providerAPIKey(.zapper).rawKey == "portu.provider.zapper.apiKey")
        #expect(KeychainKey.exchangeAPIKey(id).rawKey == "portu.exchange.\(id.uuidString).apiKey")
        #expect(KeychainKey.exchangeAPISecret(id).rawKey == "portu.exchange.\(id.uuidString).apiSecret")
        #expect(KeychainKey.exchangePassphrase(id).rawKey == "portu.exchange.\(id.uuidString).passphrase")
    }
}
