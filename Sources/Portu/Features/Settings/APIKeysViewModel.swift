import Foundation
import PortuCore

private struct APIKeysSecrets {
    let zerionAPIKey: String
    let debankAPIKey: String
    let coingeckoAPIKey: String
    let rpcEndpoints: [Chain: String]
}

private actor APIKeysSecretStore {
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    func load() throws(KeychainError) -> APIKeysSecrets {
        var rpcEndpoints: [Chain: String] = [:]
        for chain in Chain.allCases {
            if let url = try secretStore.get(key: .rpcEndpoint(chain)) {
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    rpcEndpoints[chain] = trimmed
                }
            }
        }
        return try APIKeysSecrets(
            zerionAPIKey: secretStore.get(key: .providerAPIKey(.zerion)) ?? "",
            debankAPIKey: secretStore.get(key: .serviceAPIKey("debank")) ?? "",
            coingeckoAPIKey: secretStore.get(key: .serviceAPIKey("coingecko")) ?? "",
            rpcEndpoints: rpcEndpoints)
    }

    func save(
        _ secrets: APIKeysSecrets,
        deletingRPCEndpoints removedChains: Set<Chain>) throws(KeychainError) {
        try saveKey(.providerAPIKey(.zerion), value: secrets.zerionAPIKey)
        try saveKey(.serviceAPIKey("debank"), value: secrets.debankAPIKey)
        try saveKey(.serviceAPIKey("coingecko"), value: secrets.coingeckoAPIKey)

        for (chain, url) in secrets.rpcEndpoints {
            try saveKey(.rpcEndpoint(chain), value: url)
        }
        for chain in removedChains {
            try secretStore.delete(key: .rpcEndpoint(chain))
        }
    }

    private func saveKey(_ key: KeychainKey, value: String) throws(KeychainError) {
        if value.isEmpty {
            try secretStore.delete(key: key)
        } else {
            try secretStore.set(key: key, value: value)
        }
    }
}

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
    private(set) var canSave = true

    private let secretStore: APIKeysSecretStore
    private var persistedRPCEndpointChains: Set<Chain> = []

    init(secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        self.secretStore = APIKeysSecretStore(secretStore: secretStore)
    }

    func load() async {
        isLoading = true
        canSave = false
        defer { isLoading = false; hasLoaded = true }
        secretStoreError = nil
        do {
            let secrets = try await secretStore.load()
            zerionAPIKey = secrets.zerionAPIKey
            debankAPIKey = secrets.debankAPIKey
            coingeckoAPIKey = secrets.coingeckoAPIKey
            rpcEndpoints = secrets.rpcEndpoints
            persistedRPCEndpointChains = Set(secrets.rpcEndpoints.keys)
            canSave = true
        } catch {
            secretStoreError = "Unable to access API keys in Keychain. Unlock your Mac and try again."
        }
    }

    func save() async {
        guard canSave else { return }
        secretStoreError = nil
        let normalizedRPCEndpoints = rpcEndpoints.reduce(into: [Chain: String]()) { endpoints, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                endpoints[entry.key] = trimmed
            }
        }
        rpcEndpoints = normalizedRPCEndpoints
        let secrets = APIKeysSecrets(
            zerionAPIKey: zerionAPIKey,
            debankAPIKey: debankAPIKey,
            coingeckoAPIKey: coingeckoAPIKey,
            rpcEndpoints: normalizedRPCEndpoints)
        let currentRPCEndpointChains = Set(normalizedRPCEndpoints.keys)
        let removedRPCEndpointChains = persistedRPCEndpointChains.subtracting(currentRPCEndpointChains)
        do {
            try await secretStore.save(
                secrets,
                deletingRPCEndpoints: removedRPCEndpointChains)
            persistedRPCEndpointChains = currentRPCEndpointChains
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
}
