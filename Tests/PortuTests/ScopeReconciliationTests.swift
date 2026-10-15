import Foundation
@testable import Portu
import PortuCore
import Testing

/// T2 scope reconciliation: one portfolio feeds every screen's seam, and each screen's total is
/// the Overview net total (A7). The portfolio is the shared fixture plus the inactive Cold Wallet.
/// The active-scope screens get the active accounts' tokens, as `ValuationInput.activeAccounts`
/// keeps them; Accounts gets every account and only its active balances are summed (S9). Under the
/// default dashboard settings the Assets tab and Exposure's asset table hide the dust and unpriced
/// rows, and their totals still count them through the hidden line.
struct ScopeReconciliationTests {
    private typealias Fixture = PortfolioValuationFixture
    private typealias Seam = AccountsSeamFixture

    private static let activeAccounts = [Fixture.mainAccount, Fixture.degenAccount]

    /// The all-accounts input with the inactive account's tokens left out.
    private static let activeInputs = Seam.inputs.filter { $0.position.accountId.map(activeAccounts.contains) == true }

    @Test func `the active input is the fixture without the inactive account`() {
        #expect(Self.activeInputs.map(\.tokenId) == Fixture.inputs.map(\.tokenId))
        #expect(Seam.inputs.contains { $0.position.accountId == Seam.inactiveAccount })
    }

    @Test(arguments: [Decimal(1), PortfolioValuationFixture.decimal("0.9")])
    func `every screen's total is the Overview headline total`(rate: Decimal) throws {
        let active = Fixture.context(rate: rate, inputs: Self.activeInputs)
        let headline = OverviewFeature.headline(active).total

        let assets = AllAssetsFeature.assets(active, searchText: "")
        let platforms = AllAssetsFeature.platforms(active)
        let networks = AllAssetsFeature.networks(active)
        let exposure = ExposureFeature.dashboard(active)
        let page = AllPositionsFeature.page(active, cards: AllPositionsSeamFixture.cards, filter: .all)
        let allOption = try #require(page.typeOptions.first { $0.type == nil })

        let balances = AccountsFeature.balances(Fixture.context(rate: rate, inputs: Seam.inputs))
        let activeBalances = Self.activeAccounts.compactMap { balances[$0]?.balance }
        try #require(activeBalances.count == 2)
        let inactiveBalance = try #require(balances[Seam.inactiveAccount]?.balance)

        #expect(assets.hidden != nil)
        #expect(exposure.assetHidden != nil)
        #expect(headline == Fixture.decimal("10780.4") * rate)
        #expect(platforms.total == headline)
        #expect(networks.total == headline)
        #expect(assets.total == headline)
        #expect(activeBalances.reduce(0, +) == headline)
        #expect(exposure.summary.netTotal == headline)
        #expect(allOption.total == headline)
        #expect(inactiveBalance != 0)
    }
}
