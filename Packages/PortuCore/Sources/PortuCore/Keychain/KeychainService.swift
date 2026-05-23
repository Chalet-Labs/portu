import Foundation
import Security

/// Wraps Security.framework keychain APIs. Items are scoped to the kSecAttrService value
/// (defaults to the host bundle identifier; falls back to "com.portu.app" when none is set).
///
/// Items are written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so they
/// cannot sync to iCloud Keychain and stay tied to this device.
public struct KeychainService: SecretStore {
    typealias CopyMatching = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    typealias Add = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    typealias Update = @Sendable (CFDictionary, CFDictionary) -> OSStatus
    typealias Delete = @Sendable (CFDictionary) -> OSStatus

    private let service: String
    private let copyMatching: CopyMatching
    private let add: Add
    private let update: Update
    private let delete: Delete

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.portu.app") {
        self.init(
            service: service,
            copyMatching: SecItemCopyMatching,
            add: SecItemAdd,
            update: SecItemUpdate,
            delete: SecItemDelete)
    }

    init(
        service: String,
        copyMatching: @escaping CopyMatching = SecItemCopyMatching,
        add: @escaping Add = SecItemAdd,
        update: @escaping Update = SecItemUpdate,
        delete: @escaping Delete = SecItemDelete) {
        self.service = service
        self.copyMatching = copyMatching
        self.add = add
        self.update = update
        self.delete = delete
    }

    public func get(key: KeychainKey) throws(KeychainError) -> String? {
        let query = baseQuery(for: key).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }

        return try string(matching: query)
    }

    public func set(key: KeychainKey, value: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else {
            throw .encodingFailed
        }

        let baseQuery = baseQuery(for: key)

        let addStatus = add(
            baseQuery.merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]) { _, new in new } as CFDictionary,
            nil)

        switch addStatus {
        case errSecSuccess:
            break
        case errSecDuplicateItem:
            let updateStatus = update(
                baseQuery as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                ] as CFDictionary)
            switch updateStatus {
            case errSecSuccess:
                break
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
    }

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawKey
        ]
    }

    private func string(matching query: [String: Any]) throws(KeychainError) -> String? {
        var result: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &result)

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
            throw .interactionNotAllowed
        default:
            throw .unexpectedStatus(status)
        }
    }

    private func delete(matching query: [String: Any]) throws(KeychainError) {
        let status = delete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound: break
        case errSecInteractionNotAllowed: throw .interactionNotAllowed
        default: throw .unexpectedStatus(status)
        }
    }
}
