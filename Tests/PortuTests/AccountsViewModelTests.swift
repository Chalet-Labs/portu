import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Accounts ViewModel Tests")
struct AccountsViewModelTests {
    @Test func accountRowsExposeFirstAddressOrExchangeName() throws {
        let row = try #require(AccountsViewModel.fixture().rows.first(where: { $0.name == "Kraken" }))

        #expect(row.secondaryLabel == "Kraken")
    }

    @Test func inactiveFilterHidesActiveRows() {
        let viewModel = AccountsViewModel.fixture()
        viewModel.filter = .inactive

        #expect(viewModel.visibleRows.allSatisfy { $0.isActive == false })
    }

    @Test func searchFiltersRowsByAddressOrName() {
        let viewModel = AccountsViewModel.fixture()
        viewModel.searchText = "0xabc"

        #expect(viewModel.visibleRows.map(\.name) == ["Main Wallet"])
    }

    @Test func searchMatchesSecondaryWalletAddresses() {
        let viewModel = AccountsViewModel.fixture()
        viewModel.searchText = "0xdef"

        #expect(viewModel.visibleRows.map(\.name) == ["Main Wallet"])
    }

    @Test func groupFilterRestrictsRowsToSelectedGroup() {
        let viewModel = AccountsViewModel.fixture()
        viewModel.selectedGroup = "Trading"

        #expect(viewModel.visibleRows.map(\.name) == ["Kraken"])
    }

    @Test func accountRowsProjectUsdBalanceFromPositions() throws {
        let row = try #require(AccountsViewModel.fixture().rows.first(where: { $0.name == "Main Wallet" }))

        #expect(row.usdBalance == 3_200)
    }

    @Test func togglingAccountActiveStatePreservesRowButMovesFilterBucket() throws {
        let viewModel = AccountsViewModel.fixture()

        try viewModel.toggleActiveState(for: "Kraken")

        #expect(viewModel.rows.first(where: { $0.name == "Kraken" })?.isActive == false)

        viewModel.filter = .active
        #expect(viewModel.visibleRows.contains(where: { $0.name == "Kraken" }) == false)

        viewModel.filter = .inactive
        #expect(viewModel.visibleRows.contains(where: { $0.name == "Kraken" }))
    }

    @Test func accountsViewExposesExpectedTableColumns() {
        #expect(AccountsView.tableColumnTitles == ["Name", "Group", "Address", "Type", "USD Balance"])
    }
}

@MainActor
private extension AccountsViewModel {
    static func fixture() -> AccountsViewModel {
        let wallet = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .zapper,
            group: "Core"
        )
        wallet.addresses = [
            WalletAddress(address: "0xabc", chain: nil, account: wallet),
            WalletAddress(address: "0xdef", chain: .base, account: wallet)
        ]
        wallet.positions = [
            Position(
                positionType: .idle,
                netUSDValue: 3_200,
                chain: .ethereum,
                protocolName: "Wallet",
                account: wallet
            )
        ]

        let exchange = Account(
            name: "Kraken",
            kind: .exchange,
            dataSource: .exchange,
            exchangeType: .kraken,
            group: "Trading"
        )
        exchange.positions = [
            Position(
                positionType: .idle,
                netUSDValue: 1_250,
                protocolName: "Custody",
                account: exchange
            )
        ]

        let inactiveManual = Account(
            name: "Spreadsheet",
            kind: .manual,
            dataSource: .manual,
            group: "Offline",
            isActive: false
        )
        inactiveManual.positions = [
            Position(
                positionType: .other,
                netUSDValue: 500,
                protocolName: "Manual",
                account: inactiveManual
            )
        ]

        return AccountsViewModel(accounts: [wallet, exchange, inactiveManual])
    }
}
