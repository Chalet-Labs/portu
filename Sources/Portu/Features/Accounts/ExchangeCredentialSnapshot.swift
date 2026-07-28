import Foundation
import PortuCore

struct ExchangeCredentialSnapshot: Equatable {
    var apiKey: String?
    var apiSecret: String?
    var passphrase: String?

    static let empty = Self(apiKey: nil, apiSecret: nil, passphrase: nil)
}

actor AccountCredentialStore {
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    func load(for accountID: UUID) throws(KeychainError) -> ExchangeCredentialSnapshot {
        let apiKey = try secretStore.get(key: .exchangeAPIKey(accountID))
        let apiSecret = try secretStore.get(key: .exchangeAPISecret(accountID))
        let passphrase = try secretStore.get(key: .exchangePassphrase(accountID))
        return ExchangeCredentialSnapshot(
            apiKey: apiKey,
            apiSecret: apiSecret,
            passphrase: passphrase)
    }

    func save(
        _ credentials: ExchangeCredentialSnapshot,
        for accountID: UUID,
        rollbackTo previousCredentials: ExchangeCredentialSnapshot) throws(KeychainError) {
        do {
            try write(credentials, for: accountID)
        } catch {
            restore(previousCredentials, for: accountID)
            throw error
        }
    }

    func delete(
        for accountID: UUID,
        rollbackTo previousCredentials: ExchangeCredentialSnapshot) throws(KeychainError) {
        do {
            try write(.empty, for: accountID)
        } catch {
            restore(previousCredentials, for: accountID)
            throw error
        }
    }

    func restore(_ credentials: ExchangeCredentialSnapshot, for accountID: UUID) {
        restore(credentials.apiKey, key: .exchangeAPIKey(accountID))
        restore(credentials.apiSecret, key: .exchangeAPISecret(accountID))
        restore(credentials.passphrase, key: .exchangePassphrase(accountID))
    }

    func deleteBestEffort(for accountID: UUID) {
        restore(.none, key: .exchangeAPIKey(accountID))
        restore(.none, key: .exchangeAPISecret(accountID))
        restore(.none, key: .exchangePassphrase(accountID))
    }

    private func write(
        _ credentials: ExchangeCredentialSnapshot,
        for accountID: UUID) throws(KeychainError) {
        try write(credentials.apiKey, key: .exchangeAPIKey(accountID))
        try write(credentials.apiSecret, key: .exchangeAPISecret(accountID))
        try write(credentials.passphrase, key: .exchangePassphrase(accountID))
    }

    private func write(_ value: String?, key: KeychainKey) throws(KeychainError) {
        if let value {
            try secretStore.set(key: key, value: value)
        } else {
            try secretStore.delete(key: key)
        }
    }

    private func restore(_ value: String?, key: KeychainKey) {
        try? write(value, key: key)
    }
}
