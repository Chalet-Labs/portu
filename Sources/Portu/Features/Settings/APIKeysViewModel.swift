import Foundation
import PortuCore

@MainActor
@Observable
final class APIKeysViewModel {
    var zapperAPIKey = ""
    var debankAPIKey = ""
    var coingeckoAPIKey = ""
    var rpcEndpoints: [Chain: String] = [:]
    var keychainError: String?

    private let secretStore: SecretStore

    init(secretStore: SecretStore = KeychainService()) {
        self.secretStore = secretStore
    }

    func load() {
        keychainError = nil
        do {
            zapperAPIKey = try secretStore.get(key: Keys.zapper) ?? ""
            debankAPIKey = try secretStore.get(key: Keys.debank) ?? ""
            coingeckoAPIKey = try secretStore.get(key: Keys.coingecko) ?? ""

            rpcEndpoints = [:]
            for chain in Chain.allCases {
                if let url = try secretStore.get(key: Keys.rpc(chain)), !url.isEmpty {
                    rpcEndpoints[chain] = url
                }
            }
        } catch {
            keychainError = "Unable to load API keys from Keychain. Try restarting the app."
        }
    }

    func save() {
        keychainError = nil
        do {
            try saveKey(Keys.zapper, value: zapperAPIKey)
            try saveKey(Keys.debank, value: debankAPIKey)
            try saveKey(Keys.coingecko, value: coingeckoAPIKey)

            for chain in Chain.allCases {
                if let url = rpcEndpoints[chain], !url.isEmpty {
                    try saveKey(Keys.rpc(chain), value: url)
                } else {
                    try secretStore.delete(key: Keys.rpc(chain))
                }
            }
        } catch {
            keychainError = "Unable to save API keys to Keychain. Check that the app has Keychain access."
        }
    }

    func addRPCEndpoint(chain: Chain, url: String) {
        rpcEndpoints[chain] = url
    }

    func removeRPCEndpoint(chain: Chain) {
        rpcEndpoints.removeValue(forKey: chain)
    }

    // MARK: - Private

    private func saveKey(_ key: String, value: String) throws(KeychainError) {
        if value.isEmpty {
            try secretStore.delete(key: key)
        } else {
            try secretStore.set(key: key, value: value)
        }
    }

    private enum Keys {
        static let zapper = "portu.provider.zapper.apiKey"
        static let debank = "portu.provider.debank.apiKey"
        static let coingecko = "portu.provider.coingecko.apiKey"
        static func rpc(_ chain: Chain) -> String {
            "portu.provider.rpc.\(chain.rawValue)"
        }
    }
}
