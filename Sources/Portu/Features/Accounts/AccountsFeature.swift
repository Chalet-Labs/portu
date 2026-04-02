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
    let group: String?
    let isActive: Bool
    let lastSyncError: String?
    let totalBalance: Decimal
    let firstAddress: String?
}

/// Row data for account table display.
nonisolated struct AccountRowData: Identifiable {
    let id: UUID
    let name: String
    let group: String
    let address: String
    let type: String
    let balance: Decimal
    let isActive: Bool
    let lastSyncError: String?
}

// MARK: - AccountsFeature

@Reducer
struct AccountsFeature {
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var filterGroup: String?
        var showInactive: Bool = false
        var showAddSheet: Bool = false
    }

    enum Action: Equatable {
        case searchTextChanged(String)
        case filterGroupChanged(String?)
        case showInactiveToggled
        case addSheetPresented(Bool)
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

            case let .addSheetPresented(presented):
                state.showAddSheet = presented
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Map account inputs to display rows.
    static func mapAccountRows(from accounts: [AccountInput]) -> [AccountRowData] {
        accounts.map { account in
            let address = account.firstAddress
                ?? account.exchangeType?.rawValue.capitalized
                ?? "Manual"
            let truncated = address.count > 16
                ? String(address.prefix(16)) + "\u{2026}"
                : address

            return AccountRowData(
                id: account.id,
                name: account.name,
                group: account.group ?? "\u{2014}",
                address: truncated,
                type: account.kind.rawValue.capitalized,
                balance: account.totalBalance,
                isActive: account.isActive,
                lastSyncError: account.lastSyncError
            )
        }
    }

    /// Filter account rows by active status, search text, and group.
    static func filterAccountRows(
        _ rows: [AccountRowData],
        searchText: String,
        filterGroup: String?,
        showInactive: Bool
    )
        -> [AccountRowData]
    {
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
        chainName: String,
        chainAddress: String,
        manualName: String,
        exchangeName: String,
        exchangeAPIKey: String,
        exchangeAPISecret: String
    )
        -> Bool
    {
        switch tab {
        case 0: !chainName.isEmpty && !chainAddress.isEmpty
        case 1: !manualName.isEmpty
        case 2: !exchangeName.isEmpty && !exchangeAPIKey.isEmpty && !exchangeAPISecret.isEmpty
        default: false
        }
    }
}
