import Foundation
import PortuCore

actor AccountSecretsCoordinator {
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore = KeychainService()) {
        self.secretStore = secretStore
    }

    func saveExchangeSecrets(
        accountID: UUID,
        apiKey: String,
        apiSecret: String,
        passphrase: String
    ) async throws(KeychainError) {
        var storedKeys: [KeychainKey] = []

        do {
            try await secretStore.setValue(apiKey, for: .exchangeAPIKey(accountID))
            storedKeys.append(.exchangeAPIKey(accountID))

            try await secretStore.setValue(apiSecret, for: .exchangeAPISecret(accountID))
            storedKeys.append(.exchangeAPISecret(accountID))

            let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedPassphrase.isEmpty {
                try await secretStore.removeValue(for: .exchangePassphrase(accountID))
            } else {
                try await secretStore.setValue(normalizedPassphrase, for: .exchangePassphrase(accountID))
                storedKeys.append(.exchangePassphrase(accountID))
            }
        } catch let originalError {
            var cleanupError: KeychainError?

            for key in storedKeys.reversed() {
                do {
                    try await secretStore.removeValue(for: key)
                } catch let keychainError {
                    cleanupError = cleanupError ?? keychainError
                }
            }

            if let cleanupError {
                throw cleanupError
            }

            throw originalError
        }
    }
}
