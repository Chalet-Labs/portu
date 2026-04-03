import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - Reducer Tests

@MainActor
struct AccountsFeatureTests {
    // MARK: - B1: Search Text

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

    // MARK: - B2: Group Filter

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

    // MARK: - B3: Show Inactive Toggle

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

    // MARK: - B4: Show Add Sheet

    @Test func `add sheet presentation updates state`() async {
        let store = TestStore(initialState: AccountsFeature.State()) {
            AccountsFeature()
        }

        await store.send(.addSheetPresented(true)) {
            $0.showAddSheet = true
        }
        await store.send(.addSheetPresented(false)) {
            $0.showAddSheet = false
        }
    }
}

// MARK: - B5: Account Row Mapping

struct AccountRowMappingTests {
    @Test func `maps wallet account with truncated address`() {
        let input = AccountInput(
            id: UUID(), name: "My Wallet", kind: .wallet,
            exchangeType: nil, group: "DeFi", isActive: true,
            lastSyncError: nil, totalBalance: 50000,
            firstAddress: "0x1234567890abcdef1234567890abcdef12345678")

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows.count == 1)
        #expect(rows[0].name == "My Wallet")
        #expect(rows[0].group == "DeFi")
        #expect(rows[0].address == "0x1234567890abcd\u{2026}") // 16 chars + ellipsis
        #expect(rows[0].type == "Wallet")
        #expect(rows[0].balance == 50000)
        #expect(rows[0].isActive == true)
    }

    @Test func `maps exchange account with exchange type as address`() {
        let input = AccountInput(
            id: UUID(), name: "My Kraken", kind: .exchange,
            exchangeType: .kraken, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 10000,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "Kraken")
        #expect(rows[0].group == "\u{2014}") // em dash for nil group
    }

    @Test func `maps manual account with Manual as address`() {
        let input = AccountInput(
            id: UUID(), name: "Cash Stash", kind: .manual,
            exchangeType: nil, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "Manual")
        #expect(rows[0].type == "Manual")
    }

    @Test func `short address not truncated`() {
        let input = AccountInput(
            id: UUID(), name: "Short", kind: .wallet,
            exchangeType: nil, group: nil, isActive: true,
            lastSyncError: nil, totalBalance: 0,
            firstAddress: "abc123")

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].address == "abc123") // no ellipsis
    }

    @Test func `preserves sync error`() {
        let input = AccountInput(
            id: UUID(), name: "Broken", kind: .exchange,
            exchangeType: .binance, group: nil, isActive: true,
            lastSyncError: "API rate limit", totalBalance: 0,
            firstAddress: nil)

        let rows = AccountsFeature.mapAccountRows(from: [input])

        #expect(rows[0].lastSyncError == "API rate limit")
    }
}

// MARK: - B6: Account Row Filtering

struct AccountRowFilteringTests {
    private let activeRow = AccountRowData(
        id: UUID(), name: "Active Wallet", group: "DeFi",
        address: "0x123", type: "Wallet", balance: 5000,
        isActive: true, lastSyncError: nil)
    private let inactiveRow = AccountRowData(
        id: UUID(), name: "Old Exchange", group: "CEX",
        address: "Kraken", type: "Exchange", balance: 0,
        isActive: false, lastSyncError: nil)

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
            isActive: true, lastSyncError: nil)

        let filtered = AccountsFeature.filterAccountRows(
            [activeRow, inactiveRow, defiRow],
            searchText: "wallet", filterGroup: "DeFi", showInactive: true)

        #expect(filtered.count == 2) // Active Wallet + DeFi Wallet 2
    }
}

// MARK: - B7: Group Extraction

struct AccountGroupExtractionTests {
    @Test func `extracts sorted unique groups`() {
        let inputs = [
            AccountInput(
                id: UUID(),
                name: "A",
                kind: .wallet,
                exchangeType: nil,
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

// MARK: - B8: Form Validation

struct AccountFormValidationTests {
    @Test func `chain tab requires name and address`() {
        #expect(AccountsFeature.canSave(
            tab: 0,
            chainName: "W",
            chainAddress: "0x1",
            manualName: "",
            exchangeName: "",
            exchangeAPIKey: "",
            exchangeAPISecret: "") == true)
        #expect(AccountsFeature.canSave(
            tab: 0,
            chainName: "",
            chainAddress: "0x1",
            manualName: "",
            exchangeName: "",
            exchangeAPIKey: "",
            exchangeAPISecret: "") == false)
        #expect(AccountsFeature.canSave(
            tab: 0,
            chainName: "W",
            chainAddress: "",
            manualName: "",
            exchangeName: "",
            exchangeAPIKey: "",
            exchangeAPISecret: "") == false)
    }

    @Test func `manual tab requires name`() {
        #expect(AccountsFeature.canSave(
            tab: 1,
            chainName: "",
            chainAddress: "",
            manualName: "Cash",
            exchangeName: "",
            exchangeAPIKey: "",
            exchangeAPISecret: "") == true)
        #expect(AccountsFeature.canSave(
            tab: 1,
            chainName: "",
            chainAddress: "",
            manualName: "",
            exchangeName: "",
            exchangeAPIKey: "",
            exchangeAPISecret: "") == false)
    }

    @Test func `exchange tab requires name and both keys`() {
        #expect(AccountsFeature.canSave(
            tab: 2,
            chainName: "",
            chainAddress: "",
            manualName: "",
            exchangeName: "Kraken",
            exchangeAPIKey: "key",
            exchangeAPISecret: "secret") == true)
        #expect(AccountsFeature.canSave(
            tab: 2,
            chainName: "",
            chainAddress: "",
            manualName: "",
            exchangeName: "Kraken",
            exchangeAPIKey: "",
            exchangeAPISecret: "secret") == false)
        #expect(AccountsFeature.canSave(
            tab: 2,
            chainName: "",
            chainAddress: "",
            manualName: "",
            exchangeName: "",
            exchangeAPIKey: "key",
            exchangeAPISecret: "secret") == false)
    }

    @Test func `unknown tab returns false`() {
        #expect(AccountsFeature.canSave(
            tab: 99,
            chainName: "x",
            chainAddress: "x",
            manualName: "x",
            exchangeName: "x",
            exchangeAPIKey: "x",
            exchangeAPISecret: "x") == false)
    }
}
