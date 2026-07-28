import Foundation
import PortuCore

private struct APIKeysSecrets {
    let zerionAPIKey: String
    let debankAPIKey: String
    let coingeckoAPIKey: String
    let rpcEndpoints: [Chain: String]
}

private actor APIKeysSecretStore {
    private struct Mutation {
        let key: KeychainKey
        let value: String?
    }

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
        var mutations = [
            Mutation(key: .providerAPIKey(.zerion), value: nonEmpty(secrets.zerionAPIKey)),
            Mutation(key: .serviceAPIKey("debank"), value: nonEmpty(secrets.debankAPIKey)),
            Mutation(key: .serviceAPIKey("coingecko"), value: nonEmpty(secrets.coingeckoAPIKey))
        ]
        mutations.append(contentsOf: secrets.rpcEndpoints
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { Mutation(key: .rpcEndpoint($0.key), value: $0.value) })
        mutations.append(contentsOf: removedChains
            .sorted { $0.rawValue < $1.rawValue }
            .map { Mutation(key: .rpcEndpoint($0), value: nil) })

        var changes: [(Mutation, String?)] = []
        for mutation in mutations {
            let previousValue = try secretStore.get(key: mutation.key)
            if previousValue != mutation.value {
                changes.append((mutation, previousValue))
            }
        }
        var appliedPreviousValues: [(KeychainKey, String?)] = []
        do {
            for (mutation, previousValue) in changes {
                try write(mutation.value, to: mutation.key)
                appliedPreviousValues.append((mutation.key, previousValue))
            }
        } catch let saveError {
            var firstRollbackError: KeychainError?
            for (key, previousValue) in appliedPreviousValues.reversed() {
                do {
                    try write(previousValue, to: key)
                } catch let rollbackError {
                    firstRollbackError = firstRollbackError ?? rollbackError
                }
            }
            throw firstRollbackError ?? saveError
        }
    }

    private func write(_ value: String?, to key: KeychainKey) throws(KeychainError) {
        if let value {
            try secretStore.set(key: key, value: value)
        } else {
            try secretStore.delete(key: key)
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
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
    private(set) var canSave = false

    private let secretStore: APIKeysSecretStore
    private var persistedRPCEndpointChains: Set<Chain> = []

    init(secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        self.secretStore = APIKeysSecretStore(secretStore: secretStore)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        canSave = false
        defer {
            isLoading = false
            hasLoaded = true
        }
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
            secretStoreError = Self.keychainErrorMessage(action: "access", error: error)
        }
    }

    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        secretStoreError = nil
        zerionAPIKey = zerionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        debankAPIKey = debankAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        coingeckoAPIKey = coingeckoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return true
        } catch {
            secretStoreError = Self.keychainErrorMessage(action: "save", error: error)
            return false
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

    private static func keychainErrorMessage(action: String, error: KeychainError) -> String {
        switch error {
        case .interactionNotAllowed:
            "Unable to \(action) API keys in Keychain. Unlock your Mac and try again."
        case .encodingFailed, .unexpectedStatus:
            "Unable to \(action) API keys in Keychain: \(error.localizedDescription)"
        }
    }
}
