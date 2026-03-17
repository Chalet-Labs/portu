import Foundation
import Security

/// Wraps Security.framework keychain APIs. Items are scoped to the kSecAttrService value
/// (defaults to bundle identifier).
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
            kSecUseDataProtectionKeychain as String: true,
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

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        // Add-first upsert: attempt add, then update on duplicate
        let addStatus = SecItemAdd(
            baseQuery.merging([
                kSecAttrAccessible as String: accessibility,
                kSecValueData as String: data,
            ]) { _, new in new } as CFDictionary,
            nil
        )

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: accessibility,
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw .unexpectedStatus(updateStatus)
            }
        default:
            throw .unexpectedStatus(addStatus)
        }
    }

    public func delete(key: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .unexpectedStatus(status)
        }
    }
}
