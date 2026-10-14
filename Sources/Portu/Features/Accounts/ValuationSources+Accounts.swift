import Foundation
import PortuCore

extension ValuationSources {
    /// Accounts' balances over every account. The page shows no 24h figure, so it does not read
    /// the live fractions, and it hides no row, so the dashboard settings go unused.
    func accountBalances(_ accounts: [Account]) -> [UUID: AccountBalance] {
        AccountsFeature.balances(context(AccountsFeature.valuationInputs(accounts), includingLiveChanges: false))
    }
}
