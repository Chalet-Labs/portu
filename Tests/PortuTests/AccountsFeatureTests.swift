import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct AccountsFeatureTests {
    // MARK: - Search Text

    @Test func `search text updates state`() async {
        let store = TestStore(initialState: AccountsFeature.State()) {
            AccountsFeature()
        }

        await store.send(.searchTextChanged("kraken")) {
            $0.searchText = "kraken"
        }
        await store.send(.searchTextChanged("")) {
            $0.searchText = ""
        }
    }

    // MARK: - Group Filter

    @Test func `group filter updates state`() async {
        let store = TestStore(initialState: AccountsFeature.State()) {
            AccountsFeature()
        }

        await store.send(.filterGroupChanged("DeFi")) {
            $0.filterGroup = "DeFi"
        }
        await store.send(.filterGroupChanged(nil)) {
            $0.filterGroup = nil
        }
    }

    // MARK: - Show Inactive Toggle

    @Test func `show inactive toggles state`() async {
        let store = TestStore(initialState: AccountsFeature.State()) {
            AccountsFeature()
        }

        await store.send(.showInactiveToggled) {
            $0.showInactive = true
        }
        await store.send(.showInactiveToggled) {
            $0.showInactive = false
        }
    }

    // MARK: - Account Sheet Presentation

    @Test func `add account action presents add sheet`() async {
        let store = TestStore(initialState: AccountsFeature.State()) {
            AccountsFeature()
        }

        await store.send(.addAccountTapped) {
            $0.accountSheetMode = .add
        }
        await store.send(.accountSheetDismissed) {
            $0.accountSheetMode = nil
        }
    }

    @Test func `edit account action presents edit sheet for account id`() async {
        let accountID = UUID()
        let store = TestStore(initialState: AccountsFeature.State()) {
            AccountsFeature()
        }

        await store.send(.editAccountTapped(accountID)) {
            $0.accountSheetMode = .edit(accountID)
        }
    }
}

// MARK: - Account Row Mapping

struct AccountRowMappingTests {
    @Test func `maps wallet account with full address`() {
        let input = AccountInput(
            id: UUID(), name: "My Wallet", kind: .wallet,
            exchangeType: nil, dataSource: .zapper, group: "DeFi", isActive: true,
            lastSyncError: nil, totalBalance: 50000,
            firstAddress: "0x1234567890abcdef1234567890abcdef12345678")

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows.count == 1)
        #expect(rows[0].name == "My Wallet")
        #expect(rows[0].group == "DeFi")
        #expect(rows[0].address == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(rows[0].type == "Wallet")
        #expect(rows[0].balance == 50000)
        #expect(rows[0].isActive == true)
        #expect(rows[0].isSyncable == true)
    }

    @Test func `maps exchange account with exchange type as address`() {
        let input = AccountInput(
            id: UUID(), name: "My Kraken", kind: .exchange,
            exchangeType: .kraken, dataSource: .exchange, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 10000,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "Kraken")
        #expect(rows[0].group == "\u{2014}") // em dash for nil group
        #expect(rows[0].isSyncable == true)
    }

    @Test func `maps manual account with Manual as address`() {
        let input = AccountInput(
            id: UUID(), name: "Cash Stash", kind: .manual,
            exchangeType: nil, dataSource: .manual, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "Manual")
        #expect(rows[0].type == "Manual")
        #expect(rows[0].isSyncable == false)
    }

    @Test func `maps missing wallet address as em dash`() {
        let input = AccountInput(
            id: UUID(), name: "Addressless Wallet", kind: .wallet,
            exchangeType: nil, dataSource: .zapper, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "\u{2014}")
        #expect(rows[0].type == "Wallet")
    }

    @Test func `maps missing exchange type as exchange`() {
        let input = AccountInput(
            id: UUID(), name: "Exchange", kind: .exchange,
            exchangeType: nil, dataSource: .exchange, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "Exchange")
        #expect(rows[0].type == "Exchange")
    }

    @Test func `inactive syncable source is not row syncable`() {
        let input = AccountInput(
            id: UUID(), name: "Inactive", kind: .wallet,
            exchangeType: nil, dataSource: .zapper, group: nil, isActive: false,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: "0x123")

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].isSyncable == false)
    }

    @Test func `short address not truncated`() {
        let input = AccountInput(
            id: UUID(), name: "Short", kind: .wallet,
            exchangeType: nil, dataSource: .zapper, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: "abc123")

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "abc123") // no ellipsis
    }

    @Test func `preserves sync error`() {
        let input = AccountInput(
            id: UUID(), name: "Broken", kind: .exchange,
            exchangeType: .binance, dataSource: .exchange, group: nil, isActive: true,
            lastSyncError: "API rate limit", totalBalance: 0,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].lastSyncError == "API rate limit")
    }
}

// MARK: - Account Row Filtering

struct AccountRowFilteringTests {
    private let activeRow = AccountRowData(
        id: UUID(), name: "Active Wallet", group: "DeFi",
        address: "0x123", type: "Wallet", balance: 5000,
        dataSource: .zapper, isActive: true, lastSyncError: nil)
    private let inactiveRow = AccountRowData(
        id: UUID(), name: "Old Exchange", group: "CEX",
        address: "Kraken", type: "Exchange", balance: 0,
        dataSource: .exchange, isActive: false, lastSyncError: nil)

    @Test func `hides inactive when showInactive is false`() {
        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow],
            searchText: "", filterGroup: nil, showInactive: false)

        #expect(filtered.count == 1)
        #expect(filtered[0].name == "Active Wallet")
    }

    @Test func `shows inactive when showInactive is true`() {
        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow],
            searchText: "", filterGroup: nil, showInactive: true)

        #expect(filtered.count == 2)
    }

    @Test func `filters by search text case-insensitively`() {
        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow],
            searchText: "wallet", filterGroup: nil, showInactive: true)

        #expect(filtered.count == 1)
        #expect(filtered[0].name == "Active Wallet")
    }

    @Test func `filters by group`() {
        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow],
            searchText: "", filterGroup: "CEX", showInactive: true)

        #expect(filtered.count == 1)
        #expect(filtered[0].name == "Old Exchange")
    }

    @Test func `nil group shows all`() {
        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow],
            searchText: "", filterGroup: nil, showInactive: true)

        #expect(filtered.count == 2)
    }

    @Test func `combines search and group filters`() {
        let defiRow = AccountRowData(
            id: UUID(), name: "DeFi Wallet 2", group: "DeFi",
            address: "0x456", type: "Wallet", balance: 3000,
            dataSource: .zapper, isActive: true, lastSyncError: nil)

        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow, defiRow],
            searchText: "wallet", filterGroup: "DeFi", showInactive: true)

        #expect(filtered.count == 2) // Active Wallet + DeFi Wallet 2
    }
}

// MARK: - Group Extraction

struct AccountGroupExtractionTests {
    @Test func `extracts sorted unique groups`() {
        let inputs = [
            AccountInput(
                id: UUID(),
                name: "A",
                kind: .wallet,
                exchangeType: nil,
                dataSource: .zapper,
                group: "DeFi",
                isActive: true,
                lastSyncError: nil,
                totalBalance: 0,
                firstAddress: nil),
            AccountInput(
                id: UUID(),
                name: "B",
                kind: .exchange,
                exchangeType: .kraken,
                dataSource: .exchange,
                group: "CEX",
                isActive: true,
                lastSyncError: nil,
                totalBalance: 0,
                firstAddress: nil),
            AccountInput(
                id: UUID(),
                name: "C",
                kind: .wallet,
                exchangeType: nil,
                dataSource: .zapper,
                group: "DeFi",
                isActive: true,
                lastSyncError: nil,
                totalBalance: 0,
                firstAddress: nil),
            AccountInput(
                id: UUID(),
                name: "D",
                kind: .manual,
                exchangeType: nil,
                dataSource: .manual,
                group: nil,
                isActive: true,
                lastSyncError: nil,
                totalBalance: 0,
                firstAddress: nil)
        ]

        let groups = AccountsFeature.extractGroups(from: inputs)

        #expect(groups == ["CEX", "DeFi"])
    }

    @Test func `returns empty when no groups`() {
        let inputs = [
            AccountInput(
                id: UUID(),
                name: "A",
                kind: .manual,
                exchangeType: nil,
                dataSource: .manual,
                group: nil,
                isActive: true,
                lastSyncError: nil,
                totalBalance: 0,
                firstAddress: nil)
        ]

        let groups = AccountsFeature.extractGroups(from: inputs)

        #expect(groups.isEmpty)
    }
}

// MARK: - Form Validation

struct AccountFormValidationTests {
    @Test func `chain tab requires name and address`() {
        #expect(AccountsFeature.canSave(
            tab: 0,
            fields: AccountSaveFields(chainName: "W", chainAddress: "0x1")) == true)
        #expect(AccountsFeature.canSave(
            tab: 0,
            fields: AccountSaveFields(chainAddress: "0x1")) == false)
        #expect(AccountsFeature.canSave(
            tab: 0,
            fields: AccountSaveFields(chainName: "W")) == false)
    }

    @Test func `manual tab requires name`() {
        #expect(AccountsFeature.canSave(
            tab: 1,
            fields: AccountSaveFields(manualName: "Cash")) == true)
        #expect(AccountsFeature.canSave(
            tab: 1,
            fields: AccountSaveFields()) == false)
    }

    @Test func `exchange tab requires name and both keys`() {
        #expect(AccountsFeature.canSave(
            tab: 2,
            fields: AccountSaveFields(
                exchangeName: "Kraken",
                exchangeAPIKey: "key",
                exchangeAPISecret: "secret")) == true)
        #expect(AccountsFeature.canSave(
            tab: 2,
            fields: AccountSaveFields(
                exchangeName: "Kraken",
                exchangeAPISecret: "secret")) == false)
        #expect(AccountsFeature.canSave(
            tab: 2,
            fields: AccountSaveFields(
                exchangeAPIKey: "key",
                exchangeAPISecret: "secret")) == false)
    }

    @Test func `unknown tab returns false`() {
        #expect(AccountsFeature.canSave(
            tab: 99,
            fields: AccountSaveFields(
                chainName: "x",
                chainAddress: "x",
                manualName: "x",
                exchangeName: "x",
                exchangeAPIKey: "x",
                exchangeAPISecret: "x")) == false)
    }
}

// MARK: - Sync Eligibility

struct AccountSyncEligibilityTests {
    @Test func `active non-manual accounts are syncable`() {
        #expect(AccountSyncEligibility.isSyncable(isActive: true, dataSource: .zapper))
        #expect(AccountSyncEligibility.isSyncable(isActive: true, dataSource: .exchange))
    }

    @Test func `inactive or manual accounts are not syncable`() {
        #expect(AccountSyncEligibility.isSyncable(isActive: false, dataSource: .zapper) == false)
        #expect(AccountSyncEligibility.isSyncable(isActive: false, dataSource: .exchange) == false)
        #expect(AccountSyncEligibility.isSyncable(isActive: true, dataSource: .manual) == false)
    }

    @MainActor
    @Test func `account isSyncable mirrors the shared rule`() {
        let syncable = Account(name: "W", kind: .wallet, dataSource: .zapper)
        let manual = Account(name: "M", kind: .manual, dataSource: .manual)
        let inactive = Account(name: "I", kind: .wallet, dataSource: .zapper, isActive: false)
        #expect(syncable.isSyncable)
        #expect(manual.isSyncable == false)
        #expect(inactive.isSyncable == false)
    }
}

// MARK: - Row Action Policy

struct AccountRowActionPolicyTests {
    @Test func `sync help prioritizes the selected syncing row`() {
        #expect(AccountRowActionPolicy.syncHelp(
            isActive: true,
            dataSource: .zapper,
            isSyncingThisAccount: true,
            globalSyncIsRunning: true) == "Syncing this account...")
    }

    @Test func `sync help reports another sync for different row`() {
        #expect(AccountRowActionPolicy.syncHelp(
            isActive: true,
            dataSource: .zapper,
            isSyncingThisAccount: false,
            globalSyncIsRunning: true) == "Another sync is already running.")
    }

    @Test func `delete is disabled while any sync is running`() {
        #expect(!AccountRowActionPolicy.deleteDisabled(globalSyncIsRunning: false))
        #expect(AccountRowActionPolicy.deleteDisabled(globalSyncIsRunning: true))
    }
}

// MARK: - Sheet Sync Policy

struct AccountSheetSyncPolicyTests {
    @Test func `add sheet is blocked during any sync`() {
        let policy = AccountSheetSyncPolicy.state(
            mode: .add,
            syncStatus: .syncing(progress: 0.4),
            syncingAccountID: UUID())

        #expect(policy.isSyncing == false)
        #expect(policy.isSyncBlocked == true)
    }

    @Test func `edit sheet marks selected syncing account separately from blocked accounts`() {
        let accountID = UUID()
        let selectedPolicy = AccountSheetSyncPolicy.state(
            mode: .edit(accountID),
            syncStatus: .syncing(progress: 0.4),
            syncingAccountID: accountID)
        let blockedPolicy = AccountSheetSyncPolicy.state(
            mode: .edit(UUID()),
            syncStatus: .syncing(progress: 0.4),
            syncingAccountID: accountID)

        #expect(selectedPolicy.isSyncing == true)
        #expect(selectedPolicy.isSyncBlocked == false)
        #expect(blockedPolicy.isSyncing == false)
        #expect(blockedPolicy.isSyncBlocked == true)
    }

    @Test func `sheet is editable while sync is idle`() {
        let policy = AccountSheetSyncPolicy.state(
            mode: .add,
            syncStatus: .idle,
            syncingAccountID: nil)

        #expect(policy.isSyncing == false)
        #expect(policy.isSyncBlocked == false)
    }
}
