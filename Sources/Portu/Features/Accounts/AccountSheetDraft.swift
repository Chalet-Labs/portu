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

    static func adding() -> Self {
        Self()
    }

    @MainActor
    static func editing(account: Account, secretStore: any SecretStore = LocalSecretStore()) -> Self {
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
            draft.exchangeAPIKey = (try? secretStore.get(key: .exchangeAPIKey(account.id))) ?? ""
            draft.exchangeAPISecret = (try? secretStore.get(key: .exchangeAPISecret(account.id))) ?? ""
            draft.exchangePassphrase = (try? secretStore.get(key: .exchangePassphrase(account.id))) ?? ""
        }

        return draft
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
            try update(account, from: draft, modelContext: modelContext, secretStore: secretStore)
        }
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
            account.name = draft.exchangeName
            account.exchangeType = draft.exchangeType
            account.group = nilIfEmpty(draft.exchangeGroup)
            account.notes = nilIfEmpty(draft.exchangeNotes)
            try saveExchangeCredentials(for: account.id, from: draft, secretStore: secretStore)
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
        let currentAddresses = account.addresses
        if let first = currentAddresses.first {
            first.chain = chain
            first.address = address
            first.account = account
            account.addresses = [first]

            for extra in currentAddresses.dropFirst() {
                modelContext.delete(extra)
            }
        } else {
            account.addresses = [WalletAddress(chain: chain, address: address, account: account)]
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
            } else {
                try secretStore.delete(key: .exchangePassphrase(accountID))
            }
        } catch {
            throw AccountSheetSaveError.credentialSaveFailed(error.localizedDescription)
        }
    }

    private static func deleteExchangeCredentials(_ accountID: UUID, secretStore: any SecretStore) {
        try? secretStore.delete(key: .exchangeAPIKey(accountID))
        try? secretStore.delete(key: .exchangeAPISecret(accountID))
        try? secretStore.delete(key: .exchangePassphrase(accountID))
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
