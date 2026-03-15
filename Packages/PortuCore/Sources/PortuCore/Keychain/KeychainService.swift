import Foundation
import Security

/// Wraps Security.framework Keychain APIs. Scoped by bundle ID (not sandboxed).
public struct KeychainService: SecretStore {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.portu.app") {
        self.service = service
    }

    public func get(key: String) throws(KeychainError) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else {
                throw .encodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw .unexpectedStatus(status)
        }
    }

    public func set(key: String, value: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else {
            throw .encodingFailed
        }

        // Delete existing item first (upsert pattern)
        try delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw .unexpectedStatus(status)
        }
    }

    public func delete(key: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .unexpectedStatus(status)
        }
    }
}
