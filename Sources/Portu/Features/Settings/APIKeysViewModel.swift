import Foundation
import PortuCore

@MainActor
@Observable
final class APIKeysViewModel {
    var zerionAPIKey = ""
    var debankAPIKey = ""
    var coingeckoAPIKey = ""
    var rpcEndpoints: [Chain: String] = [:]
    var secretStoreError: String?
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    private let secretStore: SecretStore

    init(secretStore: SecretStore = PortuApp.makeSecretStore()) {
        self.secretStore = secretStore
    }

    func load() {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        secretStoreError = nil
        do {
            zerionAPIKey = try secretStore.get(key: .providerAPIKey(.zerion)) ?? ""
            debankAPIKey = try secretStore.get(key: .serviceAPIKey("debank")) ?? ""
            coingeckoAPIKey = try secretStore.get(key: .serviceAPIKey("coingecko")) ?? ""

            rpcEndpoints = [:]
            for chain in Chain.allCases {
                if let url = try secretStore.get(key: .rpcEndpoint(chain)), !url.isEmpty {
                    rpcEndpoints[chain] = url
                }
            }
        } catch {
            secretStoreError = "Unable to access API keys in Keychain. Unlock your Mac and try again."
        }
    }

    func save() {
        secretStoreError = nil
        do {
            try saveKey(.providerAPIKey(.zerion), value: zerionAPIKey)
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
            secretStoreError = "Unable to save API keys in Keychain. Unlock your Mac and try again."
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
