import Foundation
import Security

/// Wraps Security.framework keychain APIs. Items are scoped to the kSecAttrService value
/// (defaults to bundle identifier).
public struct KeychainService: SecretStore {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.portu.app") {
        self.service = service
    }

    public func get(key: KeychainKey) throws(KeychainError) -> String? {
        let query = baseQuery(for: key).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }

        if let value = try string(matching: query) {
            return value
        }

        let legacyQuery = legacyBaseQuery(for: key).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        guard let legacyValue = try string(matching: legacyQuery, isLegacyFallback: true) else {
            return nil
        }

        try set(key: key, value: legacyValue)
        deleteLegacy(key: key)
        return legacyValue
    }

    public func set(key: KeychainKey, value: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else {
            throw .encodingFailed
        }

        let baseQuery = baseQuery(for: key)

        // Add-first upsert: attempt add, then update on duplicate
        let addStatus = SecItemAdd(
            baseQuery.merging([
                kSecValueData as String: data
            ]) { _, new in new } as CFDictionary,
            nil)

        switch addStatus {
        case errSecSuccess:
            deleteLegacy(key: key)
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [
                    kSecValueData as String: data
                ] as CFDictionary)
            switch updateStatus {
            case errSecSuccess:
                deleteLegacy(key: key)
            case errSecInteractionNotAllowed: throw .interactionNotAllowed
            default: throw .unexpectedStatus(updateStatus)
            }
        case errSecInteractionNotAllowed:
            throw .interactionNotAllowed
        default:
            throw .unexpectedStatus(addStatus)
        }
    }

    public func delete(key: KeychainKey) throws(KeychainError) {
        try delete(matching: baseQuery(for: key))
        deleteLegacy(key: key)
    }

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawKey
        ]
    }

    private func legacyBaseQuery(for key: KeychainKey) -> [String: Any] {
        baseQuery(for: key).merging([
            kSecUseDataProtectionKeychain as String: true
        ]) { _, new in new }
    }

    private func string(matching query: [String: Any], isLegacyFallback: Bool = false) throws(KeychainError) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let string = String(data: data, encoding: .utf8)
            else {
                throw .encodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            if isLegacyFallback {
                return nil
            }
            throw .interactionNotAllowed
        default:
            if isLegacyFallback {
                return nil
            }
            throw .unexpectedStatus(status)
        }
    }

    private func deleteLegacy(key: KeychainKey) {
        _ = SecItemDelete(legacyBaseQuery(for: key) as CFDictionary)
    }

    private func delete(matching query: [String: Any]) throws(KeychainError) {
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound: break
        case errSecInteractionNotAllowed: throw .interactionNotAllowed
        default: throw .unexpectedStatus(status)
        }
    }
}
