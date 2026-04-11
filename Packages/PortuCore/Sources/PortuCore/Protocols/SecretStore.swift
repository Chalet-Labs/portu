/// Protocol for secret storage, enabling mock injection in tests.
public protocol SecretStore: Sendable {
    func get(key: KeychainKey) throws(KeychainError) -> String?
    func set(key: KeychainKey, value: String) throws(KeychainError)
    func delete(key: KeychainKey) throws(KeychainError)
}
