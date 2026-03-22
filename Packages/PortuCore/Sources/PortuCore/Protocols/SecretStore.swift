/// Protocol for typed secret storage, enabling mock injection in tests.
public protocol SecretStore: Sendable {
    func value(for key: KeychainKey) async throws(KeychainError) -> String?
    func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError)
    func removeValue(for key: KeychainKey) async throws(KeychainError)
}
