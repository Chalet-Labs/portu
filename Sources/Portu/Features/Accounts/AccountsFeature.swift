import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

/// Lightweight input for account row mapping — decouples from SwiftData models.
struct AccountInput: Equatable {
    let id: UUID
    let name: String
    let kind: AccountKind
    let exchangeType: ExchangeType?
    let dataSource: DataSource
    let group: String?
    let isActive: Bool
    let lastSyncError: String?
    let totalBalance: Decimal
    let firstAddress: String?
}

struct AccountSaveFields: Equatable {
    var chainName: String = ""
    var chainAddress: String = ""
    var manualName: String = ""
    var exchangeName: String = ""
    var exchangeAPIKey: String = ""
    var exchangeAPISecret: String = ""
}

/// Row data for account table display.
nonisolated struct AccountRowData: Identifiable {
    let id: UUID
    let name: String
    let group: String
    let address: String
    let type: String
    let balance: Decimal
    let dataSource: DataSource
    let isActive: Bool
    let lastSyncError: String?

    var isSyncable: Bool {
        AccountSyncEligibility.isSyncable(isActive: isActive, dataSource: dataSource)
    }
}

enum AccountRowActionPolicy {
    static func syncDisabled(rowIsSyncable: Bool, globalSyncIsRunning: Bool) -> Bool {
        !rowIsSyncable || globalSyncIsRunning
    }

    static func deleteDisabled(globalSyncIsRunning: Bool) -> Bool {
        globalSyncIsRunning
    }

    static func syncHelp(
        isActive: Bool,
        dataSource: DataSource,
        isSyncingThisAccount: Bool,
        globalSyncIsRunning: Bool) -> String {
        if isSyncingThisAccount {
            return "Syncing this account..."
        }
        if globalSyncIsRunning {
            return "Another sync is already running."
        }
        if isActive == false {
            return "Inactive accounts cannot be synced."
        }
        if dataSource == .manual {
            return "Manual accounts do not sync."
        }
        return "Sync this account."
    }
}

struct AccountSheetSyncState: Equatable {
    let isSyncing: Bool
    let isSyncBlocked: Bool
}

enum AccountSheetSyncPolicy {
    static func state(
        mode: AccountSheetMode,
        syncStatus: SyncStatus,
        syncingAccountID: UUID?) -> AccountSheetSyncState {
        guard syncStatus.isSyncing else {
            return AccountSheetSyncState(isSyncing: false, isSyncBlocked: false)
        }

        switch mode {
        case .add:
            return AccountSheetSyncState(isSyncing: false, isSyncBlocked: true)

        case let .edit(accountID):
            let isSyncingThisAccount = syncingAccountID == accountID
            return AccountSheetSyncState(
                isSyncing: isSyncingThisAccount,
                isSyncBlocked: !isSyncingThisAccount)
        }
    }
}

// MARK: - AccountsFeature

enum AccountSheetMode: Equatable, Identifiable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add:
            "add"
        case let .edit(id):
            "edit-\(id.uuidString)"
        }
    }

    var editedAccountID: UUID? {
        if case let .edit(id) = self {
            return id
        }
        return nil
    }

    var isEditing: Bool {
        editedAccountID != nil
    }
}

@Reducer
struct AccountsFeature {
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var filterGroup: String?
        var showInactive: Bool = false
        var accountSheetMode: AccountSheetMode?
    }

    enum Action: Equatable {
        case searchTextChanged(String)
        case filterGroupChanged(String?)
        case showInactiveToggled
        case addAccountTapped
        case editAccountTapped(UUID)
        case accountSheetDismissed
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .searchTextChanged(text):
                state.searchText = text
                return .none

            case let .filterGroupChanged(group):
                state.filterGroup = group
                return .none

            case .showInactiveToggled:
                state.showInactive.toggle()
                return .none

            case .addAccountTapped:
                state.accountSheetMode = .add
                return .none

            case let .editAccountTapped(id):
                state.accountSheetMode = .edit(id)
                return .none

            case .accountSheetDismissed:
                state.accountSheetMode = nil
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Map account inputs to display rows.
    static func mapAccountRows(from accounts: [AccountInput]) -> [AccountRowData] {
        accounts.map { account in
            AccountRowData(
                id: account.id,
                name: account.name,
                group: account.group ?? "\u{2014}",
                address: addressDisplay(for: account),
                type: account.kind.rawValue.capitalized,
                balance: account.totalBalance,
                dataSource: account.dataSource,
                isActive: account.isActive,
                lastSyncError: account.lastSyncError)
        }
    }

    private static func addressDisplay(for account: AccountInput) -> String {
        switch account.kind {
        case .wallet:
            account.firstAddress ?? "\u{2014}"
        case .exchange:
            account.exchangeType?.rawValue.capitalized ?? "Exchange"
        case .manual:
            "Manual"
        }
    }

    /// Filter account rows by active status, search text, and group.
    static func filterAccountRows(
        _ rows: [AccountRowData],
        searchText: String,
        filterGroup: String?,
        showInactive: Bool) -> [AccountRowData] {
        rows.filter { row in
            (showInactive || row.isActive)
                && (searchText.isEmpty || row.name.localizedCaseInsensitiveContains(searchText))
                && (filterGroup == nil || row.group == filterGroup)
        }
    }

    /// Extract sorted unique group names from account inputs.
    static func extractGroups(from accounts: [AccountInput]) -> [String] {
        Array(Set(accounts.compactMap(\.group))).sorted()
    }

    /// Validate whether the add-account form can be saved for the given tab.
    static func canSave(
        tab: Int,
        fields: AccountSaveFields) -> Bool {
        func filled(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return switch tab {
        case 0: filled(fields.chainName) && filled(fields.chainAddress)
        case 1: filled(fields.manualName)
        case 2: filled(fields.exchangeName) && filled(fields.exchangeAPIKey) && filled(fields.exchangeAPISecret)
        default: false
        }
    }
}
