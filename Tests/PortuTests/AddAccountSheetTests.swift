import Foundation
import SwiftData
import Testing
import PortuCore
@testable import Portu

actor InMemorySecretStore: SecretStore {
    private var storage: [KeychainKey: String] = [:]

    func value(for key: KeychainKey) async throws(KeychainError) -> String? {
        storage[key]
    }

    func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError) {
        storage[key] = value
    }

    func removeValue(for key: KeychainKey) async throws(KeychainError) {
        storage[key] = nil
    }

    fileprivate func exchangeSecrets(for accountID: UUID) async throws(KeychainError) -> StoredExchangeSecrets {
        StoredExchangeSecrets(
            apiKey: try await value(for: .exchangeAPIKey(accountID)),
            apiSecret: try await value(for: .exchangeAPISecret(accountID)),
            passphrase: try await value(for: .exchangePassphrase(accountID))
        )
    }
}

actor FailingSecretStore: SecretStore {
    func value(for key: KeychainKey) async throws(KeychainError) -> String? {
        nil
    }

    func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError) {
        throw .unexpectedStatus(-1)
    }

    func removeValue(for key: KeychainKey) async throws(KeychainError) {
    }
}

actor CleanupFailingSecretStore: SecretStore {
    private var storage: [KeychainKey: String] = [:]

    func value(for key: KeychainKey) async throws(KeychainError) -> String? {
        storage[key]
    }

    func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError) {
        switch key {
        case .exchangeAPISecret:
            throw .unexpectedStatus(-1)
        default:
            storage[key] = value
        }
    }

    func removeValue(for key: KeychainKey) async throws(KeychainError) {
        switch key {
        case .exchangeAPIKey:
            throw .unexpectedStatus(-2)
        default:
            storage[key] = nil
        }
    }
}

fileprivate struct StoredExchangeSecrets: Equatable {
    let apiKey: String?
    let apiSecret: String?
    let passphrase: String?
}

@MainActor
@Suite("Add Account Sheet Tests")
struct AddAccountSheetTests {
    @Test func addAccountSheetExposesAllEntryTabs() {
        #expect(AddAccountSheet.tabTitles == ["Chain Account", "Manual Account", "Exchange Account"])
    }

    @Test func chainAccountFormCreatesNilChainForEVMAddress() throws {
        let harness = try AddAccountSheetHarness.make()

        try harness.submitChainAccount(
            name: "Main Wallet",
            ecosystem: .evm,
            address: "0xabc"
        )

        let account = try #require(try harness.savedAccounts().first)
        let address = try #require(account.addresses.first)

        #expect(account.kind == .wallet)
        #expect(account.dataSource == .zapper)
        #expect(address.chain == nil)
    }

    @Test func manualAccountFormCreatesManualAccountWithoutAddresses() throws {
        let harness = try AddAccountSheetHarness.make()

        try harness.submitManualAccount(
            name: "Manual Ledger",
            notes: "Offline holdings"
        )

        let account = try #require(try harness.savedAccounts().first)

        #expect(account.kind == .manual)
        #expect(account.dataSource == .manual)
        #expect(account.notes == "Offline holdings")
        #expect(account.addresses.isEmpty)
    }

    @Test func exchangeAccountFormStoresSecretsViaCoordinator() async throws {
        let harness = try AddAccountSheetHarness.make()

        let accountID = try await harness.submitExchangeAccount(
            name: "Kraken",
            exchangeType: .kraken,
            apiKey: "key",
            apiSecret: "secret",
            passphrase: "passphrase"
        )

        let account = try #require(try harness.savedAccounts().first)
        let storedSecrets = try await harness.secretStore.exchangeSecrets(for: accountID)

        #expect(account.kind == .exchange)
        #expect(account.dataSource == .exchange)
        #expect(account.exchangeType == .kraken)
        #expect(storedSecrets == StoredExchangeSecrets(apiKey: "key", apiSecret: "secret", passphrase: "passphrase"))
    }

    @Test func exchangeAccountFormRollsBackAccountWhenSecretPersistenceFails() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let submission = ExchangeAccountForm.Submission(
            name: "Kraken",
            exchangeType: .kraken,
            apiKey: "key",
            apiSecret: "secret",
            passphrase: "passphrase"
        )

        do {
            _ = try await submission.save(
                in: container.mainContext,
                secretsCoordinator: AccountSecretsCoordinator(secretStore: FailingSecretStore())
            )
            Issue.record("Expected secret persistence failure")
        } catch {
            #expect(error is KeychainError)
        }

        let accounts = try container.mainContext.fetch(FetchDescriptor<Account>())
        #expect(accounts.isEmpty)
    }

    @Test func accountSecretsCoordinatorSurfacesCleanupFailure() async throws {
        let accountID = UUID()
        let secretStore = CleanupFailingSecretStore()
        let coordinator = AccountSecretsCoordinator(secretStore: secretStore)

        do {
            try await coordinator.saveExchangeSecrets(
                accountID: accountID,
                apiKey: "key",
                apiSecret: "secret",
                passphrase: ""
            )
            Issue.record("Expected cleanup failure")
        } catch let error as KeychainError {
            switch error {
            case .unexpectedStatus(let status):
                #expect(status == -2)
            default:
                Issue.record("Expected cleanup removal failure, got \(error)")
            }
        }

        let persistedKey = try await secretStore.value(for: .exchangeAPIKey(accountID))
        #expect(persistedKey == "key")
    }
}

@MainActor
private struct AddAccountSheetHarness {
    let container: ModelContainer
    let secretStore: InMemorySecretStore
    let secretsCoordinator: AccountSecretsCoordinator

    static func make() throws -> Self {
        let container = try ModelContainerFactory().makeInMemory()
        let secretStore = InMemorySecretStore()
        let secretsCoordinator = AccountSecretsCoordinator(secretStore: secretStore)

        return Self(
            container: container,
            secretStore: secretStore,
            secretsCoordinator: secretsCoordinator
        )
    }

    func submitChainAccount(
        name: String,
        ecosystem: ChainAccountForm.Ecosystem,
        address: String
    ) throws {
        let submission = ChainAccountForm.Submission(
            name: name,
            ecosystem: ecosystem,
            address: address
        )

        _ = try submission.save(in: container.mainContext)
    }

    func submitManualAccount(
        name: String,
        notes: String
    ) throws {
        let submission = ManualAccountForm.Submission(
            name: name,
            notes: notes
        )

        _ = try submission.save(in: container.mainContext)
    }

    func submitExchangeAccount(
        name: String,
        exchangeType: ExchangeType,
        apiKey: String,
        apiSecret: String,
        passphrase: String
    ) async throws -> UUID {
        let submission = ExchangeAccountForm.Submission(
            name: name,
            exchangeType: exchangeType,
            apiKey: apiKey,
            apiSecret: apiSecret,
            passphrase: passphrase
        )

        let account = try await submission.save(
            in: container.mainContext,
            secretsCoordinator: secretsCoordinator
        )
        return account.id
    }

    func savedAccounts() throws -> [Account] {
        try container.mainContext.fetch(FetchDescriptor<Account>())
    }
}
