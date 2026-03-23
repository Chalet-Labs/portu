import Foundation
import PortuCore

enum AccountsViewModelError: Error {
    case accountNotFound(String)
}

@MainActor
@Observable
final class AccountsViewModel {
    var searchText = ""
    var filter: AccountFilter = .all
    var selectedGroup: String?
    var rows: [AccountRowModel]
    private let accountLookup: [UUID: Account]

    init(accounts: [Account] = []) {
        accountLookup = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        rows = Self.makeRows(from: accounts)
    }

    var visibleRows: [AccountRowModel] {
        rows
            .filter(matchesSearch)
            .filter(matchesFilter)
            .filter(matchesGroup)
            .sorted(by: compareRows)
    }

    var availableGroups: [String] {
        Array(
            Set(
                rows
                    .map(\.groupName)
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    func toggleActiveState(for name: String) throws {
        guard let rowID = rows.first(where: { $0.name == name })?.id else {
            throw AccountsViewModelError.accountNotFound(name)
        }

        try toggleActiveState(for: rowID)
    }

    func toggleActiveState(for id: UUID) throws {
        guard let account = accountLookup[id] else {
            throw AccountsViewModelError.accountNotFound(id.uuidString)
        }

        account.isActive.toggle()
        refreshRows()
    }

    func toggleActionTitle(for row: AccountRowModel) -> String {
        row.isActive ? "Mark Inactive" : "Mark Active"
    }

    private func matchesSearch(_ row: AccountRowModel) -> Bool {
        guard !searchText.isEmpty else {
            return true
        }

        let needle = searchText.localizedLowercase
        return row.searchIndex.localizedLowercase.contains(needle)
    }

    private func matchesFilter(_ row: AccountRowModel) -> Bool {
        switch filter {
        case .all:
            return true
        case .active:
            return row.isActive
        case .inactive:
            return !row.isActive
        }
    }

    private func matchesGroup(_ row: AccountRowModel) -> Bool {
        guard let selectedGroup, !selectedGroup.isEmpty else {
            return true
        }

        return row.groupName == selectedGroup
    }

    private static func makeRows(from accounts: [Account]) -> [AccountRowModel] {
        accounts.map { account in
            AccountRowModel(
                id: account.id,
                name: account.name,
                groupName: account.group ?? "",
                secondaryLabel: secondaryLabel(for: account),
                searchIndex: searchIndex(for: account),
                typeLabel: account.kind.rawValue.capitalized,
                usdBalance: account.positions.reduce(.zero) { $0 + $1.netUSDValue },
                isActive: account.isActive
            )
        }
    }

    private static func secondaryLabel(for account: Account) -> String {
        if account.kind == .exchange {
            return account.exchangeType?.rawValue.capitalized ?? account.name
        }

        if let firstAddress = account.addresses.first?.address {
            return firstAddress
        }

        return account.name
    }

    private static func searchIndex(for account: Account) -> String {
        let exchangeLabel = account.exchangeType?.rawValue.capitalized ?? ""
        let addresses = account.addresses.map(\.address).joined(separator: " ")

        return [
            account.name,
            account.group ?? "",
            account.kind.rawValue.capitalized,
            exchangeLabel,
            addresses
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func compareRows(_ lhs: AccountRowModel, _ rhs: AccountRowModel) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive && !rhs.isActive
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func refreshRows() {
        rows = Self.makeRows(from: Array(accountLookup.values))
    }
}
