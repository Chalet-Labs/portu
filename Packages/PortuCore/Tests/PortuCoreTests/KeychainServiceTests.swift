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
}

struct KeychainServiceTests {
    @Test func `set stores values in data protection keychain`() throws {
        let recorder = KeychainOperationRecorder()
        let store = KeychainService(
            service: "com.portu.tests",
            add: { attributes, _ in
                recorder.appendAdded(attributes.dictionaryValue)
                return errSecSuccess
            })

        try store.set(key: .providerAPIKey(.zapper), value: "zapper-token")

        let addQuery = try #require(recorder.addedQueries.first)
        #expect(addQuery.usesDataProtectionKeychain)
        #expect(addQuery[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func `get reads data protection keychain before migrating legacy item`() throws {
        let legacyValue = "legacy-zapper-token"
        let legacyData = try #require(legacyValue.data(using: .utf8))
        let recorder = KeychainOperationRecorder()

        let store = KeychainService(
            service: "com.portu.tests",
            copyMatching: { query, result in
                let copyCount = recorder.appendCopy(query.dictionaryValue)

                guard copyCount == 2 else {
                    return errSecItemNotFound
                }

                result?.pointee = legacyData as CFData
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
        let addedQueries = recorder.addedQueries
        let deletedQueries = recorder.deletedQueries

        #expect(value == legacyValue)
        #expect(copyQueries.count == 2)
        #expect(copyQueries[0].usesDataProtectionKeychain)
        #expect(!copyQueries[1].usesDataProtectionKeychain)
        #expect(try #require(addedQueries.first).usesDataProtectionKeychain)
        #expect(try !#require(deletedQueries.first).usesDataProtectionKeychain)
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
}
