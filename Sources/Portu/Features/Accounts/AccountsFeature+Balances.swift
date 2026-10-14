import Foundation
import PortuCore

/// One account's balance and its provider total at last sync (A6), in the display currency.
struct AccountBalance: Equatable {
    let balance: Decimal
    let providerTotal: Decimal

    static let zero = AccountBalance(balance: 0, providerTotal: 0)
}

extension AccountsFeature {
    /// Every account's balance: Σ the contributions of its own tokens, active or not (S9, A7). The
    /// provider total is the sync-time total (A6) beside it. An account with no input is absent; it
    /// reads as zero.
    static func balances(_ context: ValuationContext) -> [UUID: AccountBalance] {
        let byAccount = context.valuation().totals(groupedBy: { $0.position.accountId })
        var balances: [UUID: AccountBalance] = [:]
        for (accountId, totals) in byAccount {
            guard let accountId else { continue }
            let display = totals.display(rate: context.usdToDisplayRate)
            balances[accountId] = AccountBalance(balance: display.net, providerTotal: display.syncTotal)
        }
        return balances
    }

    /// The Accounts input (S9): the tokens of every account, active or not.
    @MainActor
    static func valuationInputs(_ accounts: [Account]) -> [ValuationInput] {
        ValuationInput.allAccounts(accounts.flatMap { $0.positions.flatMap(\.tokens) })
    }
}

enum AccountsFormat {
    static let providerTotalLabel = "Provider total at last sync"

    static func currency(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code))
    }

    /// The Balance cell's tooltip.
    static func providerTotalHelp(_ providerTotal: Decimal, code: String) -> String {
        "\(providerTotalLabel): \(currency(providerTotal, code: code))"
    }
}
