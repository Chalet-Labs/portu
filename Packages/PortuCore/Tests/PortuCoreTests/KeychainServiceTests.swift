import Foundation
@testable import PortuCore
import Security
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

    @Test func `local secret store persists without keychain`() throws {
        let suiteName = "com.portu.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalSecretStore(suiteName: suiteName, keyPrefix: "test.")

        try store.set(key: .providerAPIKey(.zapper), value: "zapper-token")

        #expect(defaults.string(forKey: "test.portu.provider.zapper.apiKey") == "zapper-token")
        #expect(try store.get(key: .providerAPIKey(.zapper)) == "zapper-token")

        try store.delete(key: .providerAPIKey(.zapper))

        #expect(try store.get(key: .providerAPIKey(.zapper)) == nil)
    }
}

struct KeychainServiceTests {
    @Test func `set stores values in standard keychain with ThisDeviceOnly accessibility`() throws {
        let recorder = KeychainOperationRecorder()
        let store = KeychainService(
            service: "com.portu.tests",
            add: { attributes, _ in
                recorder.appendAdded(attributes.dictionaryValue)
                return errSecSuccess
            },
            delete: { query in
                recorder.appendDeleted(query.dictionaryValue)
                return errSecSuccess
            })

        try store.set(key: .providerAPIKey(.zapper), value: "zapper-token")

        let addQuery = try #require(recorder.addedQueries.first)
        #expect(!addQuery.usesDataProtectionKeychain)
        #expect(addQuery.accessibility == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect(recorder.deletedQueries.isEmpty)
    }

    @Test func `set update path also pins ThisDeviceOnly accessibility`() throws {
        let recorder = KeychainOperationRecorder()
        let store = KeychainService(
            service: "com.portu.tests",
            add: { _, _ in errSecDuplicateItem },
            update: { _, attributes in
                recorder.appendAdded(attributes.dictionaryValue)
                return errSecSuccess
            },
            delete: { _ in errSecSuccess })

        try store.set(key: .providerAPIKey(.zapper), value: "zapper-token")

        let updateAttributes = try #require(recorder.addedQueries.first)
        #expect(updateAttributes.accessibility == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
    }

    @Test func `get reads standard keychain`() throws {
        let storedValue = "zapper-token"
        let storedData = try #require(storedValue.data(using: .utf8))
        let recorder = KeychainOperationRecorder()

        let store = KeychainService(
            service: "com.portu.tests",
            copyMatching: { query, result in
                _ = recorder.appendCopy(query.dictionaryValue)
                result?.pointee = storedData as CFData
                return errSecSuccess
            },
            add: { attributes, _ in
                recorder.appendAdded(attributes.dictionaryValue)
                return errSecSuccess
            },
            delete: { query in
                recorder.appendDeleted(query.dictionaryValue)
                return errSecSuccess
            })

        let value = try store.get(key: .providerAPIKey(.zapper))
        let copyQueries = recorder.copyQueries

        #expect(value == storedValue)
        #expect(copyQueries.count == 1)
        #expect(!copyQueries[0].usesDataProtectionKeychain)
        #expect(recorder.addedQueries.isEmpty)
        #expect(recorder.deletedQueries.isEmpty)
    }
}

private final class KeychainOperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var copyQueryStorage: [[String: Any]] = []
    private var addedQueryStorage: [[String: Any]] = []
    private var deletedQueryStorage: [[String: Any]] = []

    var copyQueries: [[String: Any]] {
        lock.withLock { copyQueryStorage }
    }

    var addedQueries: [[String: Any]] {
        lock.withLock { addedQueryStorage }
    }

    var deletedQueries: [[String: Any]] {
        lock.withLock { deletedQueryStorage }
    }

    func appendCopy(_ query: [String: Any]) -> Int {
        lock.withLock {
            copyQueryStorage.append(query)
            return copyQueryStorage.count
        }
    }

    func appendAdded(_ query: [String: Any]) {
        lock.withLock {
            addedQueryStorage.append(query)
        }
    }

    func appendDeleted(_ query: [String: Any]) {
        lock.withLock {
            deletedQueryStorage.append(query)
        }
    }
}

private extension CFDictionary {
    var dictionaryValue: [String: Any] {
        self as NSDictionary as? [String: Any] ?? [:]
    }
}

private extension [String: Any] {
    var usesDataProtectionKeychain: Bool {
        self[kSecUseDataProtectionKeychain as String] as? Bool == true
    }

    var accessibility: String? {
        self[kSecAttrAccessible as String] as? String
    }
}
