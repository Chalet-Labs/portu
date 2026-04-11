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
    private(set) var isLoading = false

    private let secretStore: SecretStore

    init(secretStore: SecretStore = KeychainService()) {
        self.secretStore = secretStore
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        keychainError = nil
        do {
            zapperAPIKey = try secretStore.get(key: .providerAPIKey(.zapper)) ?? ""
            debankAPIKey = try secretStore.get(key: .serviceAPIKey("debank")) ?? ""
            coingeckoAPIKey = try secretStore.get(key: .serviceAPIKey("coingecko")) ?? ""

            rpcEndpoints = [:]
            for chain in Chain.allCases {
                if let url = try secretStore.get(key: .rpcEndpoint(chain)), !url.isEmpty {
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
            try saveKey(.providerAPIKey(.zapper), value: zapperAPIKey)
            try saveKey(.serviceAPIKey("debank"), value: debankAPIKey)
            try saveKey(.serviceAPIKey("coingecko"), value: coingeckoAPIKey)

            for chain in Chain.allCases {
                if let url = rpcEndpoints[chain], !url.isEmpty {
                    try saveKey(.rpcEndpoint(chain), value: url)
                } else {
                    try secretStore.delete(key: .rpcEndpoint(chain))
                }
            }
        } catch {
            keychainError = "Unable to save API keys to Keychain. Check that the app has Keychain access."
        }
    }

    func addRPCEndpoint(chain: Chain, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rpcEndpoints[chain] = trimmed
    }

    func removeRPCEndpoint(chain: Chain) {
        rpcEndpoints.removeValue(forKey: chain)
    }

    // MARK: - Private

    private func saveKey(_ key: KeychainKey, value: String) throws(KeychainError) {
        if value.isEmpty {
            try secretStore.delete(key: key)
        } else {
            try secretStore.set(key: key, value: value)
        }
    }
}
