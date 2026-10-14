import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// Accounts rendered over the in-memory store and read back from its table (S9). The seeded
/// Primary Wallet holds ETH 2 (synced at 6000, live 3050) and an Aave V3 USDC supply of 4000 and
/// borrow of 500 (live 1), so its balance is 6100 + 3500 = 9600 against a provider total of 9500.
extension ViewRenderSmokeTests {
    /// "Number changes → Accounts": the balance is Σ contributions at the live value, and the new
    /// "Provider total at last sync" tooltip shows on every account, a manual one included
    /// (AGENT-DECIDED 12). The manual account's 1 ETH was entered at 3000 and is now live at 3050.
    @Test(.renderedTextReadable) func `accounts show live balances with the provider total tooltip`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let eth = try #require(context.fetch(FetchDescriptor<Asset>()).first { $0.symbol == "ETH" })
        let manual = Account(name: "Cold Storage", kind: .manual, dataSource: .manual)
        context.insert(manual)
        context.insert(Position(
            positionType: .idle,
            netUSDValue: 3000,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 3000, asset: eth)],
            account: manual))
        try context.save()

        let (cells, code) = try readAccountBalances(in: container, until: { $0.count == 2 })
        let currency = { (value: Decimal) in AccountsFormat.currency(value, code: code) }
        let help = { (value: Decimal) in AccountsFormat.providerTotalHelp(value, code: code) }

        try #require(cells.count == 2, "\(cells)")
        #expect(cells.map(\.texts) == [[currency(3050)], [currency(9600)]], "\(cells)")
        #expect(cells.map(\.help) == [help(3000), help(9500)], "\(cells)")
    }

    struct BalanceCell: Equatable {
        let texts: [String]
        let help: String?
    }

    /// Each row's Balance cell: its texts and its tooltip. `Table` keeps its cells out of the
    /// accessibility tree, so they are read from the table view itself.
    private static func balanceCells(_ view: NSView) -> [BalanceCell] {
        guard
            let table = tableView(in: view),
            let column = table.tableColumns.firstIndex(where: { $0.title == "Balance" })
        else { return [] }
        return (0 ..< table.numberOfRows).compactMap { row in
            table.view(atColumn: column, row: row, makeIfNecessary: true).map { cell in
                BalanceCell(texts: OverviewModelWiringTests.accessibilityTexts(cell), help: helpText(cell))
            }
        }
    }

    /// The first tooltip in the element's subtree, read through `accessibilityHelp`.
    private static func helpText(_ element: Any) -> String? {
        let object = element as AnyObject
        let selector = NSSelectorFromString("accessibilityHelp")
        if
            let object = object as? NSObject,
            object.responds(to: selector),
            let help = object.perform(selector)?.takeUnretainedValue() as? String,
            !help.isEmpty {
            return help
        }
        for child in object.accessibilityChildren?() ?? [] {
            if let help = helpText(child) {
                return help
            }
        }
        return nil
    }

    /// Renders the page and reads it, spinning the run loop until `isReady` or two seconds pass.
    /// Returns the cells and the currency code they are shown in.
    private func readAccountBalances(
        in container: ModelContainer,
        until isReady: ([BalanceCell]) -> Bool) throws -> (cells: [BalanceCell], currencyCode: String) {
        let store = makeStore(section: .accounts)
        let appState = AppState()
        appState.bridge(from: store)
        let hostingView = render(
            AccountsView(store: store, secretStore: InMemorySecretStore())
                .modelContainer(container)
                .environment(appState)
                .frame(width: 1400, height: 900))

        var cells = Self.balanceCells(hostingView)
        let deadline = Date().addingTimeInterval(2)
        while !isReady(cells), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            cells = Self.balanceCells(hostingView)
        }
        return (cells, appState.currencyCode)
    }
}
