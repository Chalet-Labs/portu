import Testing
@testable import PortuCore

/// In-memory mock for testing code that depends on SecretStore.
final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func get(key: String) throws(KeychainError) -> String? {
        storage[key]
    }

    func set(key: String, value: String) throws(KeychainError) {
        storage[key] = value
    }

    func delete(key: String) throws(KeychainError) {
        storage.removeValue(forKey: key)
    }
}

@Suite("SecretStore Tests")
struct SecretStoreTests {
    @Test func storeAndRetrieve() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.abc123.apiKey", value: "my-secret-key")
        let retrieved = try store.get(key: "portu.abc123.apiKey")
        #expect(retrieved == "my-secret-key")
    }

    @Test func retrieveNonExistent() throws {
        let store = MockSecretStore()
        let result = try store.get(key: "portu.missing.apiKey")
        #expect(result == nil)
    }

    @Test func deleteKey() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.abc123.apiKey", value: "secret")
        try store.delete(key: "portu.abc123.apiKey")
        let result = try store.get(key: "portu.abc123.apiKey")
        #expect(result == nil)
    }

    @Test func overwriteExistingKey() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.abc123.apiKey", value: "old")
        try store.set(key: "portu.abc123.apiKey", value: "new")
        let result = try store.get(key: "portu.abc123.apiKey")
        #expect(result == "new")
    }
}
