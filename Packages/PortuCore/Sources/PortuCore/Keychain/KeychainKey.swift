import Foundation

/// Typed keys for secrets stored in the keychain.
/// Centralizes key naming to prevent string typos and makes all keys discoverable.
public enum KeychainKey: Hashable, Sendable {
    case providerAPIKey(DataSource)
    case serviceAPIKey(String)
    case exchangeAPIKey(UUID)
    case exchangeAPISecret(UUID)
    case exchangePassphrase(UUID)
    case rpcEndpoint(Chain)

    /// The raw string used as kSecAttrAccount in Security.framework queries.
    public var rawKey: String {
        switch self {
        case let .providerAPIKey(source):
            "portu.provider.\(source.rawValue).apiKey"
        case let .serviceAPIKey(service):
            "portu.provider.\(service).apiKey"
        case let .exchangeAPIKey(id):
            "portu.exchange.\(id.uuidString).apiKey"
        case let .exchangeAPISecret(id):
            "portu.exchange.\(id.uuidString).apiSecret"
        case let .exchangePassphrase(id):
            "portu.exchange.\(id.uuidString).passphrase"
        case let .rpcEndpoint(chain):
            "portu.provider.rpc.\(chain.rawValue)"
        }
    }
}
