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
            let apiKey = try secretStore.get(key: .exchangeAPIKey(accountID)) ?? ""
            let apiSecret = try secretStore.get(key: .exchangeAPISecret(accountID)) ?? ""
            let passphrase = try secretStore.get(key: .exchangePassphrase(accountID)) ?? ""
            exchangeAPIKey = apiKey
            exchangeAPISecret = apiSecret
            exchangePassphrase = passphrase
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

enum AccountSheetSaveCoordinator {
    @MainActor
    static func save(
        draft: AccountSheetDraft,
        mode: AccountSheetMode,
        editing account: Account?,
        modelContext: ModelContext,
        secretStore: any SecretStore = PortuApp.makeSecretStore()) throws {
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
            if !draft.isEVM, draft.specificChain == .bitcoin {
                throw AccountSheetSaveError.unsupportedChain("Bitcoin")
            }
            let account = Account(
                name: draft.chainName,
                kind: .wallet,
                dataSource: .zerion,
                group: nilIfEmpty(draft.chainGroup),
                notes: nilIfEmpty(draft.chainNotes))
            modelContext.insert(account)
            let walletAddress = WalletAddress(
                chain: draft.isEVM ? nil : draft.specificChain,
                address: draft.chainAddress,
                account: account)
            modelContext.insert(walletAddress)
            account.addresses = [walletAddress]
            try saveInsertedWalletAccount(account, walletAddress: walletAddress, modelContext: modelContext)

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
            let emptyCredentials = ExchangeCredentialSnapshot.empty

            do {
                try saveExchangeCredentials(
                    for: accountID,
                    from: draft,
                    secretStore: secretStore,
                    rollbackTo: emptyCredentials)
            } catch {
                deleteExchangeCredentialsBestEffort(accountID, secretStore: secretStore)
                throw error
            }

            do {
                try insertAndSave(account, modelContext: modelContext)
            } catch {
                deleteExchangeCredentialsBestEffort(accountID, secretStore: secretStore)
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
            let chain = draft.isEVM ? nil : draft.specificChain
            let identityChanged = walletIdentityChanged(
                for: account,
                chain: chain,
                address: draft.chainAddress)
            account.name = draft.chainName
            account.group = nilIfEmpty(draft.chainGroup)
            account.notes = nilIfEmpty(draft.chainNotes)
            replaceWalletAddress(
                for: account,
                chain: chain,
                address: draft.chainAddress,
                modelContext: modelContext)
            if identityChanged {
                invalidateSyncedPositions(for: account, modelContext: modelContext)
            }

        case .manual:
            account.name = draft.manualName
            account.group = nilIfEmpty(draft.manualGroup)
            account.notes = nilIfEmpty(draft.manualNotes)

        case .exchange:
            // Persist credentials first. If the keychain write fails the model is left
            // untouched, so autosave can't flush a renamed account that still points at
            // the old secrets.
            let previousCredentials = try readExchangeCredentials(for: account.id, secretStore: secretStore)
            let credentialsAfterSave = exchangeCredentialsAfterApplying(
                draft,
                previousCredentials: previousCredentials)
            let identityChanged = account.exchangeType != draft.exchangeType || previousCredentials != credentialsAfterSave
            try saveExchangeCredentials(
                for: account.id,
                from: draft,
                secretStore: secretStore,
                rollbackTo: previousCredentials)
            account.name = draft.exchangeName
            account.exchangeType = draft.exchangeType
            account.group = nilIfEmpty(draft.exchangeGroup)
            account.notes = nilIfEmpty(draft.exchangeNotes)
            if identityChanged {
                invalidateSyncedPositions(for: account, modelContext: modelContext)
            }

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                restoreExchangeCredentials(previousCredentials, for: account.id, secretStore: secretStore)
                throw AccountSheetSaveError.accountSaveFailed(error.localizedDescription)
            }
            return
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
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
        let existingAddresses = Array(account.addresses)
        for existing in existingAddresses {
            modelContext.delete(existing)
        }
        let newAddress = WalletAddress(chain: chain, address: address, account: account)
        modelContext.insert(newAddress)
        account.addresses = [newAddress]
    }

    @MainActor
    private static func walletIdentityChanged(for account: Account, chain: Chain?, address: String) -> Bool {
        let addresses = Array(account.addresses)
        guard addresses.count == 1, let existing = addresses.first else {
            return true
        }
        return existing.chain != chain || existing.address != address
    }

    @MainActor
    private static func invalidateSyncedPositions(for account: Account, modelContext: ModelContext) {
        for position in Array(account.positions) {
            modelContext.delete(position)
        }
        account.lastSyncedAt = nil
        account.lastSyncError = nil
    }

    @MainActor
    private static func saveInsertedWalletAccount(
        _ account: Account,
        walletAddress: WalletAddress,
        modelContext: ModelContext) throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(walletAddress)
            modelContext.delete(account)
            throw AccountSheetSaveError.accountSaveFailed(error.localizedDescription)
        }
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

    @MainActor
    static func deleteAccount(
        _ account: Account,
        modelContext: ModelContext,
        secretStore: any SecretStore,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws {
        let accountID = account.id
        let isExchange = account.kind == .exchange
        let previousCredentials = if isExchange {
            try readExchangeCredentials(for: accountID, secretStore: secretStore)
        } else {
            ExchangeCredentialSnapshot.empty
        }
        if isExchange {
            do {
                try deleteExchangeCredentials(accountID, secretStore: secretStore)
            } catch {
                restoreExchangeCredentials(previousCredentials, for: accountID, secretStore: secretStore)
                throw AccountSheetSaveError.credentialSaveFailed(error.localizedDescription)
            }
        }
        modelContext.delete(account)
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            if isExchange {
                restoreExchangeCredentials(previousCredentials, for: accountID, secretStore: secretStore)
            }
            throw AccountSheetSaveError.accountSaveFailed(error.localizedDescription)
        }
    }

    @MainActor
    static func setAccount(
        _ account: Account,
        isActive: Bool,
        modelContext: ModelContext,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws {
        let previousValue = account.isActive
        account.isActive = isActive
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            account.isActive = previousValue
            throw AccountSheetSaveError.accountSaveFailed(error.localizedDescription)
        }
    }

    private static func saveExchangeCredentials(
        for accountID: UUID,
        from draft: AccountSheetDraft,
        secretStore: any SecretStore,
        rollbackTo previousCredentials: ExchangeCredentialSnapshot) throws {
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
            restoreExchangeCredentials(previousCredentials, for: accountID, secretStore: secretStore)
            throw AccountSheetSaveError.credentialSaveFailed(error.localizedDescription)
        }
    }

    private static func exchangeCredentialsAfterApplying(
        _ draft: AccountSheetDraft,
        previousCredentials: ExchangeCredentialSnapshot) -> ExchangeCredentialSnapshot {
        let passphrase: String? = if
            let persistedPassphrase = AddAccountExchangeSecrets.persistedPassphrase(
                draft.exchangePassphrase,
                for: draft.exchangeType) {
            persistedPassphrase
        } else if draft.exchangeCredentialsLoaded {
            nil
        } else {
            previousCredentials.passphrase
        }
        return ExchangeCredentialSnapshot(
            apiKey: draft.exchangeAPIKey,
            apiSecret: draft.exchangeAPISecret,
            passphrase: passphrase)
    }

    private static func readExchangeCredentials(
        for accountID: UUID,
        secretStore: any SecretStore) throws -> ExchangeCredentialSnapshot {
        do {
            return try ExchangeCredentialSnapshot(
                apiKey: secretStore.get(key: .exchangeAPIKey(accountID)),
                apiSecret: secretStore.get(key: .exchangeAPISecret(accountID)),
                passphrase: secretStore.get(key: .exchangePassphrase(accountID)))
        } catch {
            throw AccountSheetSaveError.credentialSaveFailed(error.localizedDescription)
        }
    }

    private static func restoreExchangeCredentials(
        _ snapshot: ExchangeCredentialSnapshot,
        for accountID: UUID,
        secretStore: any SecretStore) {
        restore(snapshot.apiKey, key: .exchangeAPIKey(accountID), secretStore: secretStore)
        restore(snapshot.apiSecret, key: .exchangeAPISecret(accountID), secretStore: secretStore)
        restore(snapshot.passphrase, key: .exchangePassphrase(accountID), secretStore: secretStore)
    }

    private static func restore(_ value: String?, key: KeychainKey, secretStore: any SecretStore) {
        if let value {
            try? secretStore.set(key: key, value: value)
        } else {
            try? secretStore.delete(key: key)
        }
    }

    /// Removes all keychain entries for an account. Safe to call for non-exchange
    /// accounts (deletes of missing keys are no-ops); used both by the failure-cleanup
    /// paths here and by account deletion.
    static func deleteExchangeCredentials(_ accountID: UUID, secretStore: any SecretStore) throws {
        try secretStore.delete(key: .exchangeAPIKey(accountID))
        try secretStore.delete(key: .exchangeAPISecret(accountID))
        try secretStore.delete(key: .exchangePassphrase(accountID))
    }

    private static func deleteExchangeCredentialsBestEffort(_ accountID: UUID, secretStore: any SecretStore) {
        try? secretStore.delete(key: .exchangeAPIKey(accountID))
        try? secretStore.delete(key: .exchangeAPISecret(accountID))
        try? secretStore.delete(key: .exchangePassphrase(accountID))
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
