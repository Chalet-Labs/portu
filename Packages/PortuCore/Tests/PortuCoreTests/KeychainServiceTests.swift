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
        #expect(KeychainKey.providerAPIKey(.zerion).rawKey == "portu.provider.zerion.apiKey")
        #expect(KeychainKey.providerAPIKey(.zerion) != .providerAPIKey(.zapper))
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

    @Test func `secret migration verifies keychain copy before removing plaintext`() throws {
        let source = MigrationTestSecretStore()
        let destination = MigrationTestSecretStore()
        let key = KeychainKey.serviceAPIKey("coingecko")
        try source.set(key: key, value: "secret")

        try SecretStoreMigration.migrate(keys: [key], from: source, to: destination)

        #expect(try destination.get(key: key) == "secret")
        #expect(try source.get(key: key) == nil)
    }

    @Test func `secret migration leaves plaintext when keychain write fails`() throws {
        let source = MigrationTestSecretStore()
        let destination = MigrationTestSecretStore()
        let key = KeychainKey.serviceAPIKey("coingecko")
        try source.set(key: key, value: "secret")
        destination.setError = .interactionNotAllowed

        #expect(throws: KeychainError.interactionNotAllowed) {
            try SecretStoreMigration.migrate(keys: [key], from: source, to: destination)
        }
        #expect(try source.get(key: key) == "secret")
        #expect(try destination.get(key: key) == nil)
    }

    @Test func `secret migration removes conflicting plaintext and keeps secure value`() throws {
        let source = MigrationTestSecretStore()
        let destination = MigrationTestSecretStore()
        let key = KeychainKey.serviceAPIKey("coingecko")
        try source.set(key: key, value: "obsolete-plaintext")
        try destination.set(key: key, value: "authoritative-secure")

        try SecretStoreMigration.migrate(keys: [key], from: source, to: destination)

        #expect(try source.get(key: key) == nil)
        #expect(try destination.get(key: key) == "authoritative-secure")
    }

    @Test func `secret migration continues with later keys after one key fails`() throws {
        let source = MigrationTestSecretStore()
        let destination = MigrationTestSecretStore()
        let failingKey = KeychainKey.exchangeAPIKey(UUID())
        let laterKey = KeychainKey.providerAPIKey(.zerion)
        try source.set(key: failingKey, value: "exchange-secret")
        try source.set(key: laterKey, value: "zerion-secret")
        destination.setErrors[failingKey.rawKey] = .interactionNotAllowed

        #expect(throws: KeychainError.interactionNotAllowed) {
            try SecretStoreMigration.migrate(
                keys: [failingKey, laterKey],
                from: source,
                to: destination)
        }

        #expect(try source.get(key: failingKey) == "exchange-secret")
        #expect(try destination.get(key: failingKey) == nil)
        #expect(try source.get(key: laterKey) == nil)
        #expect(try destination.get(key: laterKey) == "zerion-secret")
    }
}

struct KeychainServiceTests {
    @Test func `set stores values in data protection keychain with ThisDeviceOnly accessibility`() throws {
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
        #expect(addQuery.usesDataProtectionKeychain)
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

    @Test func `get reads data protection keychain`() throws {
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
        #expect(copyQueries[0].usesDataProtectionKeychain)
        #expect(recorder.addedQueries.isEmpty)
        #expect(recorder.deletedQueries.isEmpty)
    }

    @Test func `delete uses data protection keychain`() throws {
        let recorder = KeychainOperationRecorder()
        let store = KeychainService(
            service: "com.portu.tests",
            delete: { query in
                recorder.appendDeleted(query.dictionaryValue)
                return errSecSuccess
            })

        try store.delete(key: .providerAPIKey(.zerion))

        let deleteQuery = try #require(recorder.deletedQueries.first)
        #expect(deleteQuery.usesDataProtectionKeychain)
    }

    @Test func `repeated gets read a credential from keychain only once`() throws {
        let storedValue = "zerion-token"
        let storedData = try #require(storedValue.data(using: .utf8))
        let recorder = KeychainOperationRecorder()
        let store = KeychainService(
            service: "com.portu.tests.\(UUID().uuidString)",
            copyMatching: { query, result in
                _ = recorder.appendCopy(query.dictionaryValue)
                result?.pointee = storedData as CFData
                return errSecSuccess
            })

        #expect(try store.get(key: .providerAPIKey(.zerion)) == storedValue)
        #expect(try store.get(key: .providerAPIKey(.zerion)) == storedValue)
        #expect(recorder.copyQueries.count == 1)
    }

    @Test func `successful writes and deletes update the read cache`() throws {
        let oldData = Data("old-token".utf8)
        let recorder = KeychainOperationRecorder()
        let store = KeychainService(
            service: "com.portu.tests.\(UUID().uuidString)",
            copyMatching: { query, result in
                _ = recorder.appendCopy(query.dictionaryValue)
                result?.pointee = oldData as CFData
                return errSecSuccess
            },
            add: { _, _ in errSecSuccess },
            delete: { _ in errSecSuccess })
        let key = KeychainKey.providerAPIKey(.zerion)

        #expect(try store.get(key: key) == "old-token")
        try store.set(key: key, value: "new-token")
        #expect(try store.get(key: key) == "new-token")
        try store.delete(key: key)
        #expect(try store.get(key: key) == nil)
        #expect(recorder.copyQueries.count == 1)
    }

    @Test func `security operations are serialized across service instances`() async {
        let probe = KeychainConcurrencyProbe()
        let first = KeychainService(
            service: "com.portu.tests.first",
            copyMatching: { _, _ in
                probe.performBlockingOperation()
                return errSecItemNotFound
            })
        let second = KeychainService(
            service: "com.portu.tests.second",
            copyMatching: { _, _ in
                probe.performBlockingOperation()
                return errSecItemNotFound
            })

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 12 {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? first : second
                    _ = try? store.get(key: .providerAPIKey(.zerion))
                }
            }
        }

        #expect(probe.maximumConcurrentOperations == 1)
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

private final class KeychainConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activeOperations = 0
    private var maximumConcurrentOperationsStorage = 0

    var maximumConcurrentOperations: Int {
        lock.withLock { maximumConcurrentOperationsStorage }
    }

    func performBlockingOperation() {
        lock.withLock {
            activeOperations += 1
            maximumConcurrentOperationsStorage = max(maximumConcurrentOperationsStorage, activeOperations)
        }
        Thread.sleep(forTimeInterval: 0.05)
        lock.withLock {
            activeOperations -= 1
        }
    }
}

private final class MigrationTestSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    var setError: KeychainError?
    var setErrors: [String: KeychainError] = [:]

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        lock.withLock { storage[key.rawKey] }
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        if let error = setErrors[key.rawKey] { throw error }
        if let setError { throw setError }
        lock.withLock { storage[key.rawKey] = value }
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        _ = lock.withLock { storage.removeValue(forKey: key.rawKey) }
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
