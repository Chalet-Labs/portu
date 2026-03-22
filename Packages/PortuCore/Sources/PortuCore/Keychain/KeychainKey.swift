import Foundation

/// Stable typed keys for secrets stored in the keychain.
public enum KeychainKey: Hashable, Sendable {
    case providerAPIKey(DataSource)
    case exchangeAPIKey(UUID)
    case exchangeAPISecret(UUID)
    case exchangePassphrase(UUID)

    public var service: String {
        switch self {
        case .providerAPIKey(let dataSource):
            return "portu.provider.\(dataSource.rawValue).apiKey"
        case .exchangeAPIKey(let accountID):
            return "portu.exchange.\(accountID.uuidString).apiKey"
        case .exchangeAPISecret(let accountID):
            return "portu.exchange.\(accountID.uuidString).apiSecret"
        case .exchangePassphrase(let accountID):
            return "portu.exchange.\(accountID.uuidString).passphrase"
        }
    }
}
