/// Protocol for secret storage, enabling mock injection in tests.
/// Key naming convention: "portu.<accountId>.<credentialType>"
/// Example: "portu.abc123.apiKey", "portu.abc123.apiSecret"
public protocol SecretStore: Sendable {
    func get(key: String) throws(KeychainError) -> String?
    func set(key: String, value: String) throws(KeychainError)
    func delete(key: String) throws(KeychainError)
}
