import Foundation
import PortuCore
import SwiftData

struct AccountSheetDraft: Equatable {
    var selectedTab: AddAccountTab = .chain

    var chainName = ""
    var chainAddress = ""
    var chainGroup = ""
    var chainNotes = ""
    var isEVM = true
    var specificChain: Chain = .solana

    var manualName = ""
    var manualNotes = ""
    var manualGroup = ""

    var exchangeName = ""
    var exchangeType: ExchangeType = .kraken
    var exchangeAPIKey = ""
    var exchangeAPISecret = ""
    var exchangePassphrase = ""
    var exchangeGroup = ""
    var exchangeNotes = ""

    /// Whether the exchange credentials were read back from the keychain successfully.
    /// Stays `true` for non-exchange drafts and before a load is attempted; set to
    /// `false` if a keychain read fails so saving never blindly overwrites or deletes
    /// secrets it could not load.
    var exchangeCredentialsLoaded = true

    static func adding() -> Self {
        Self()
    }

    /// Builds an edit draft from the account's non-secret fields only. Keychain
    /// reads are deliberately excluded so this can run in a SwiftUI view initializer
    /// without side effects; load credentials separately via `loadExchangeCredentials`.
    @MainActor
    static func editing(account: Account) -> Self {
        var draft = Self()

        switch account.kind {
        case .wallet:
            draft.selectedTab = .chain
            draft.chainName = account.name
            draft.chainGroup = account.group ?? ""
            draft.chainNotes = account.notes ?? ""
            if let address = account.addresses.first {
                draft.chainAddress = address.address
                if let chain = address.chain {
                    draft.isEVM = false
                    draft.specificChain = chain
                } else {
                    draft.isEVM = true
                }
            }

        case .manual:
            draft.selectedTab = .manual
            draft.manualName = account.name
            draft.manualGroup = account.group ?? ""
            draft.manualNotes = account.notes ?? ""

        case .exchange:
            draft.selectedTab = .exchange
            draft.exchangeName = account.name
            draft.exchangeType = account.exchangeType ?? .kraken
            draft.exchangeGroup = account.group ?? ""
            draft.exchangeNotes = account.notes ?? ""
        }

        return draft
    }

    /// Builds an edit draft and eagerly loads exchange credentials. Performs keychain
    /// I/O, so call off the view-initializer path (tests, or `loadExchangeCredentials`).
    @MainActor
    static func editing(account: Account, secretStore: any SecretStore) -> Self {
        var draft = editing(account: account)
        if account.kind == .exchange {
            draft.loadExchangeCredentials(accountID: account.id, secretStore: secretStore)
        }
        return draft
    }

    /// Reads exchange credentials from the keychain into the draft. A read failure is
    /// recorded in `exchangeCredentialsLoaded` (rather than being silently coalesced to
    /// an empty string) so the save path can avoid clobbering secrets it never loaded.
    mutating func loadExchangeCredentials(accountID: UUID, secretStore: any SecretStore) {
        do {
            exchangeAPIKey = try secretStore.get(key: .exchangeAPIKey(accountID)) ?? ""
            exchangeAPISecret = try secretStore.get(key: .exchangeAPISecret(accountID)) ?? ""
            exchangePassphrase = try secretStore.get(key: .exchangePassphrase(accountID)) ?? ""
            exchangeCredentialsLoaded = true
        } catch {
            exchangeCredentialsLoaded = false
        }
    }

    var canSave: Bool {
        AccountsFeature.canSave(
            tab: selectedTab.rawValue,
            fields: AccountSaveFields(
                chainName: chainName,
                chainAddress: chainAddress,
                manualName: manualName,
                exchangeName: exchangeName,
                exchangeAPIKey: exchangeAPIKey,
                exchangeAPISecret: exchangeAPISecret))
    }
}

enum AccountSheetSaveError: Error, LocalizedError, Equatable {
    case missingEditedAccount
    case editedAccountMismatch
    case credentialSaveFailed(String)
    case accountSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEditedAccount:
            "The account being edited is no longer available."
        case .editedAccountMismatch:
            "The account being edited does not match the open sheet."
        case let .credentialSaveFailed(message):
            "Failed to save credentials: \(message)"
        case let .accountSaveFailed(message):
            "Failed to save account: \(message)"
        }
    }
}

enum AccountSheetSaveCoordinator {
    @MainActor
    static func save(
        draft: AccountSheetDraft,
        mode: AccountSheetMode,
        editing account: Account?,
        modelContext: ModelContext,
        secretStore: any SecretStore = LocalSecretStore()) throws {
        switch mode {
        case .add:
            try insertAccount(from: draft, modelContext: modelContext, secretStore: secretStore)

        case let .edit(accountID):
            guard let account else {
                throw AccountSheetSaveError.missingEditedAccount
            }
            guard account.id == accountID else {
                throw AccountSheetSaveError.editedAccountMismatch
            }
            // The captured Account may have been deleted while the sheet was open
            // (e.g. via the table context menu). Mutating + saving a tombstoned model
            // is undefined; confirm it still lives in the context first.
            guard accountExists(id: accountID, modelContext: modelContext) else {
                throw AccountSheetSaveError.missingEditedAccount
            }
            try update(account, from: draft, modelContext: modelContext, secretStore: secretStore)
        }
    }

    @MainActor
    private static func accountExists(id: UUID, modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.isEmpty == false
    }

    @MainActor
    private static func insertAccount(
        from draft: AccountSheetDraft,
        modelContext: ModelContext,
        secretStore: any SecretStore) throws {
        switch draft.selectedTab {
        case .chain:
            let account = Account(
                name: draft.chainName,
                kind: .wallet,
                dataSource: .zapper,
                group: nilIfEmpty(draft.chainGroup),
                notes: nilIfEmpty(draft.chainNotes))
            account.addresses = [
                WalletAddress(
                    chain: draft.isEVM ? nil : draft.specificChain,
                    address: draft.chainAddress,
                    account: account)
            ]
            try insertAndSave(account, modelContext: modelContext)

        case .manual:
            let account = Account(
                name: draft.manualName,
                kind: .manual,
                dataSource: .manual,
                group: nilIfEmpty(draft.manualGroup),
                notes: nilIfEmpty(draft.manualNotes))
            try insertAndSave(account, modelContext: modelContext)

        case .exchange:
            let accountID = UUID()
            let account = Account(
                id: accountID,
                name: draft.exchangeName,
                kind: .exchange,
                exchangeType: draft.exchangeType,
                dataSource: .exchange,
                group: nilIfEmpty(draft.exchangeGroup),
                notes: nilIfEmpty(draft.exchangeNotes))

            do {
                try saveExchangeCredentials(for: accountID, from: draft, secretStore: secretStore)
            } catch {
                deleteExchangeCredentials(accountID, secretStore: secretStore)
                throw error
            }

            do {
                try insertAndSave(account, modelContext: modelContext)
            } catch {
                deleteExchangeCredentials(accountID, secretStore: secretStore)
                throw error
            }
        }
    }

    @MainActor
    private static func update(
        _ account: Account,
        from draft: AccountSheetDraft,
        modelContext: ModelContext,
        secretStore: any SecretStore) throws {
        switch account.kind {
        case .wallet:
            account.name = draft.chainName
            account.group = nilIfEmpty(draft.chainGroup)
            account.notes = nilIfEmpty(draft.chainNotes)
            replaceWalletAddress(
                for: account,
                chain: draft.isEVM ? nil : draft.specificChain,
                address: draft.chainAddress,
                modelContext: modelContext)

        case .manual:
            account.name = draft.manualName
            account.group = nilIfEmpty(draft.manualGroup)
            account.notes = nilIfEmpty(draft.manualNotes)

        case .exchange:
            // Persist credentials first. If the keychain write fails the model is left
            // untouched, so autosave can't flush a renamed account that still points at
            // the old secrets.
            try saveExchangeCredentials(for: account.id, from: draft, secretStore: secretStore)
            account.name = draft.exchangeName
            account.exchangeType = draft.exchangeType
            account.group = nilIfEmpty(draft.exchangeGroup)
            account.notes = nilIfEmpty(draft.exchangeNotes)
        }

        do {
            try modelContext.save()
        } catch {
            throw AccountSheetSaveError.accountSaveFailed(error.localizedDescription)
        }
    }

    @MainActor
    private static func replaceWalletAddress(
        for account: Account,
        chain: Chain?,
        address: String,
        modelContext: ModelContext) {
        // Replace the whole address set with a single fresh row. Mutating an existing
        // row in place reused its identity (stale position resolution after a chain
        // change) and relied on the non-deterministic order of an unordered to-many;
        // recreating is deterministic and handles the empty/multi-address cases alike.
        for existing in account.addresses {
            modelContext.delete(existing)
        }
        account.addresses = [WalletAddress(chain: chain, address: address, account: account)]
    }

    @MainActor
    private static func insertAndSave(_ account: Account, modelContext: ModelContext) throws {
        modelContext.insert(account)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(account)
            throw AccountSheetSaveError.accountSaveFailed(error.localizedDescription)
        }
    }

    private static func saveExchangeCredentials(
        for accountID: UUID,
        from draft: AccountSheetDraft,
        secretStore: any SecretStore) throws {
        do {
            try secretStore.set(key: .exchangeAPIKey(accountID), value: draft.exchangeAPIKey)
            try secretStore.set(key: .exchangeAPISecret(accountID), value: draft.exchangeAPISecret)
            if
                let passphrase = AddAccountExchangeSecrets.persistedPassphrase(
                    draft.exchangePassphrase,
                    for: draft.exchangeType) {
                try secretStore.set(key: .exchangePassphrase(accountID), value: passphrase)
            } else if draft.exchangeCredentialsLoaded {
                // Only delete when we know the prior state: a blank field after a
                // failed credential read must not be mistaken for "user cleared it".
                try secretStore.delete(key: .exchangePassphrase(accountID))
            }
        } catch {
            throw AccountSheetSaveError.credentialSaveFailed(error.localizedDescription)
        }
    }

    /// Removes all keychain entries for an account. Safe to call for non-exchange
    /// accounts (deletes of missing keys are no-ops); used both by the failure-cleanup
    /// paths here and by account deletion.
    static func deleteExchangeCredentials(_ accountID: UUID, secretStore: any SecretStore) {
        try? secretStore.delete(key: .exchangeAPIKey(accountID))
        try? secretStore.delete(key: .exchangeAPISecret(accountID))
        try? secretStore.delete(key: .exchangePassphrase(accountID))
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
