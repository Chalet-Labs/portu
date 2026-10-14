import Foundation
@testable import Portu
import Testing

/// Rows that tie on the sorted column fall back to name, then account ID, so the table keeps one
/// order while balances move with live prices. Each case starts from the reverse of that order.
struct AccountRowSortingTests {
    private func row(_ name: String, id: UUID = UUID(), group: String = "DeFi", balance: Decimal = 0) -> AccountRowData {
        AccountRowData(
            id: id, name: name, group: group,
            address: "0x123", type: "Wallet", balance: balance,
            dataSource: .zerion, isActive: true, lastSyncError: nil)
    }

    @Test func `equal balances order by name`() {
        let sorted = AccountsFeature.sortAccountRows(
            [row("Zed"), row("Alpha"), row("Mid", balance: 50)],
            using: [KeyPathComparator(\.balance, order: .reverse)])

        #expect(sorted.map(\.name) == ["Mid", "Alpha", "Zed"])
    }

    @Test func `equal groups order by name`() {
        let sorted = AccountsFeature.sortAccountRows(
            [row("Zed"), row("Alpha"), row("Beta", group: "CEX")],
            using: [KeyPathComparator(\.group)])

        #expect(sorted.map(\.name) == ["Beta", "Alpha", "Zed"])
    }

    @Test func `equal names order by account ID`() throws {
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        let sorted = AccountsFeature.sortAccountRows(
            [row("Wallet", id: second), row("Wallet", id: first)],
            using: [KeyPathComparator(\.name)])

        #expect(sorted.map(\.id) == [first, second])
    }
}
