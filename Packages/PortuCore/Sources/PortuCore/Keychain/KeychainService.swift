import Foundation
import Security

/// Wraps Security.framework keychain APIs behind an actor-isolated secret store.
public actor KeychainService: SecretStore {
    private let accountName: String

    public init(accountName: String = "credential") {
        self.accountName = accountName
    }

    public func value(for key: KeychainKey) async throws(KeychainError) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: accountName,
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
                throw .decodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw .interactionNotAllowed
        default:
            throw .unexpectedStatus(status)
        }
    }

    public func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError) {
        guard let data = value.data(using: .utf8) else {
            throw .encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: accountName,
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
            switch updateStatus {
            case errSecSuccess:
                return
            case errSecInteractionNotAllowed:
                throw .interactionNotAllowed
            default:
                throw .unexpectedStatus(updateStatus)
            }
        case errSecInteractionNotAllowed:
            throw .interactionNotAllowed
        default:
            throw .unexpectedStatus(addStatus)
        }
    }

    public func removeValue(for key: KeychainKey) async throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: accountName,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecInteractionNotAllowed:
            throw .interactionNotAllowed
        default:
            throw .unexpectedStatus(status)
        }
    }
}
