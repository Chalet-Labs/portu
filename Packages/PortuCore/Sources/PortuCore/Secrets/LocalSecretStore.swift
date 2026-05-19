import Foundation

/// Stores provider credentials in app-local preferences instead of macOS Keychain.
public struct LocalSecretStore: SecretStore {
    private let suiteName: String?
    private let keyPrefix: String

    public init(suiteName: String? = nil, keyPrefix: String = "local.") {
        self.suiteName = suiteName
        self.keyPrefix = keyPrefix
    }

    public func get(key: KeychainKey) throws(KeychainError) -> String? {
        defaults.string(forKey: storageKey(for: key))
    }

    public func set(key: KeychainKey, value: String) throws(KeychainError) {
        defaults.set(value, forKey: storageKey(for: key))
    }

    public func delete(key: KeychainKey) throws(KeychainError) {
        defaults.removeObject(forKey: storageKey(for: key))
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private func storageKey(for key: KeychainKey) -> String {
        keyPrefix + key.rawKey
    }
}
