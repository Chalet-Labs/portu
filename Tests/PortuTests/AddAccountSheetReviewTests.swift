import Foundation
@testable import Portu
import PortuCore
import Testing

struct AddAccountExchangeSecretsTests {
    @Test func `passphrase is persisted only for Coinbase`() {
        #expect(AddAccountExchangeSecrets.persistedPassphrase("phrase", for: .coinbase) == "phrase")
        #expect(AddAccountExchangeSecrets.persistedPassphrase("phrase", for: .kraken) == nil)
        #expect(AddAccountExchangeSecrets.persistedPassphrase("phrase", for: .binance) == nil)
        #expect(AddAccountExchangeSecrets.persistedPassphrase("", for: .coinbase) == nil)
    }

    @Test func `switching away from Coinbase clears passphrase`() {
        #expect(AddAccountExchangeSecrets.passphraseAfterSelecting(.coinbase, currentPassphrase: "phrase") == "phrase")
        #expect(AddAccountExchangeSecrets.passphraseAfterSelecting(.kraken, currentPassphrase: "phrase").isEmpty)
        #expect(AddAccountExchangeSecrets.passphraseAfterSelecting(.binance, currentPassphrase: "phrase").isEmpty)
    }
}

struct AddAccountAccessibilityTests {
    @Test func `close icon button has explicit accessible label`() {
        #expect(AddAccountAccessibility.closeButtonLabel == "Close")
    }

    @Test func `close icon button uses mode agnostic accessible hint`() {
        #expect(AddAccountAccessibility.closeButtonHint == "Closes the account sheet.")
    }
}

struct AddAccountSheetSavePolicyTests {
    @Test func `save policy blocks submit while syncing`() {
        #expect(AddAccountSheetSavePolicy.canSubmit(
            draftCanSave: true,
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            exchangeCredentialsLoaded: true))
        #expect(!AddAccountSheetSavePolicy.canSubmit(
            draftCanSave: false,
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            exchangeCredentialsLoaded: true))
        #expect(!AddAccountSheetSavePolicy.canSubmit(
            draftCanSave: true,
            isSyncing: true,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            exchangeCredentialsLoaded: true))
        #expect(!AddAccountSheetSavePolicy.canSubmit(
            draftCanSave: true,
            isSyncing: false,
            isSyncBlocked: true,
            isLoadingCredentials: false,
            exchangeCredentialsLoaded: true))
        #expect(!AddAccountSheetSavePolicy.canSubmit(
            draftCanSave: true,
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: true,
            exchangeCredentialsLoaded: true))
    }

    @Test func `save policy blocks submit when exchange credentials failed to load`() {
        #expect(!AddAccountSheetSavePolicy.canSubmit(
            draftCanSave: true,
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            exchangeCredentialsLoaded: false))
    }

    @Test func `credential load recovery offers retry only after a completed failure`() {
        #expect(AddAccountCredentialLoadRecovery.shouldOfferRetry(
            exchangeCredentialsLoaded: false,
            isLoadingCredentials: false))
        #expect(!AddAccountCredentialLoadRecovery.shouldOfferRetry(
            exchangeCredentialsLoaded: false,
            isLoadingCredentials: true))
        #expect(!AddAccountCredentialLoadRecovery.shouldOfferRetry(
            exchangeCredentialsLoaded: true,
            isLoadingCredentials: false))
    }

    @Test func `save policy blocks field editing while syncing`() {
        #expect(AddAccountSheetSavePolicy.canEditFields(
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            isSaving: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(
            isSyncing: true,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            isSaving: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(
            isSyncing: false,
            isSyncBlocked: true,
            isLoadingCredentials: false,
            isSaving: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: true,
            isSaving: false))
        #expect(!AddAccountSheetSavePolicy.canEditFields(
            isSyncing: false,
            isSyncBlocked: false,
            isLoadingCredentials: false,
            isSaving: true))
    }
}

@MainActor
struct AccountCredentialLoadRecoveryTests {
    @Test func `credential loading and retry task are explicitly main actor isolated`() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appending(
                path: "Sources/Portu/Features/Accounts/AddAccountSheetCredentialLoading.swift"),
            encoding: .utf8)
        let normalizedSource = source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        #expect(normalizedSource.contains("@MainActor func loadCredentialsIfNeeded() async"))
        #expect(normalizedSource.contains("@MainActor func retryCredentialLoad()"))
        #expect(normalizedSource.contains("Task { @MainActor in"))
        #expect(normalizedSource.contains(
            "didLoadCredentials = true isLoadingCredentials = true defer { isLoadingCredentials = false }"))
    }

    @Test func `credential load reports failure and can recover on retry`() async {
        let accountID = UUID()
        let store = InMemorySecretStore()
        store.storage[.exchangeAPIKey(accountID)] = "stored-key"
        store.storage[.exchangeAPISecret(accountID)] = "stored-secret"
        store.throwOnGet = true
        var draft = AccountSheetDraft()
        let baseline = draft

        let loadResult = await draft.loadExchangeCredentials(accountID: accountID, secretStore: store)
        draft.exchangeAPIKey = "replacement-key"
        draft.exchangeAPISecret = "replacement-secret"
        store.throwOnGet = false
        let retryResult = await draft.loadExchangeCredentials(
            accountID: accountID,
            secretStore: store,
            preservingEditsSince: baseline)

        #expect(loadResult.error != nil)
        #expect(retryResult.error == nil)
        #expect(retryResult.storedCredentials?.apiKey == "stored-key")
        #expect(draft.exchangeCredentialsLoaded)
        #expect(draft.exchangeAPIKey == "replacement-key")
        #expect(draft.exchangeAPISecret == "replacement-secret")
    }
}
