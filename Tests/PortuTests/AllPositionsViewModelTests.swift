import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("All Positions ViewModel Tests")
struct AllPositionsViewModelTests {
    @Test func positionsGroupByTypeThenProtocolAndUseNetUsdValueForHeaders() throws {
        let viewModel = AllPositionsViewModel.fixture()

        #expect(viewModel.sections.map(\.title).prefix(2) == ["Idle Onchain", "Idle Exchanges"])

        let idleOnchain = try #require(viewModel.sections.first(where: { $0.title == "Idle Onchain" }))
        let lending = try #require(viewModel.sections.first(where: { $0.title == "Lending" }))
        let euler = try #require(lending.children.first)

        #expect(idleOnchain.value == 3_200)
        #expect(lending.value == -2_400)
        #expect(euler.protocolName == "Euler")
        #expect(euler.chainLabel == "Ethereum")
        #expect(euler.healthFactor == 1.8)
    }

    @Test func protocolSectionsStayGroupedAcrossChains() throws {
        let account = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let usdc = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )

        let arbitrumPosition = Position(
            positionType: .lending,
            netUSDValue: 500,
            chain: .arbitrum,
            protocolId: "aave-v3",
            protocolName: "Aave V3",
            healthFactor: 1.8,
            account: account
        )
        arbitrumPosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 500,
                usdValue: 500,
                asset: usdc,
                position: arbitrumPosition
            )
        ]

        let basePosition = Position(
            positionType: .lending,
            netUSDValue: 700,
            chain: .base,
            protocolId: "aave-v3",
            protocolName: "Aave V3",
            healthFactor: 1.2,
            account: account
        )
        basePosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 700,
                usdValue: 700,
                asset: usdc,
                position: basePosition
            )
        ]

        let lending = try #require(
            AllPositionsViewModel(positions: [arbitrumPosition, basePosition]).sections.first(where: { $0.title == "Lending" })
        )
        let protocolSection = try #require(lending.children.first)

        #expect(lending.children.count == 1)
        #expect(protocolSection.protocolName == "Aave V3")
        #expect(protocolSection.chainLabel == "Arbitrum / Base")
        #expect(protocolSection.healthFactor == 1.2)
    }

    @Test func protocolSectionsKeepDistinctProtocolIDsWhenNamesMatch() throws {
        let account = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let usdc = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )
        let first = Position(
            positionType: .lending,
            netUSDValue: 500,
            chain: .arbitrum,
            protocolId: "aave-v3",
            protocolName: "Aave V3",
            account: account
        )
        first.tokens = [
            PositionToken(
                role: .supply,
                amount: 500,
                usdValue: 500,
                asset: usdc,
                position: first
            )
        ]
        let second = Position(
            positionType: .lending,
            netUSDValue: 700,
            chain: .base,
            protocolId: "aave-v4",
            protocolName: "Aave V3",
            account: account
        )
        second.tokens = [
            PositionToken(
                role: .supply,
                amount: 700,
                usdValue: 700,
                asset: usdc,
                position: second
            )
        ]

        let lending = try #require(
            AllPositionsViewModel(positions: [first, second]).sections.first(where: { $0.title == "Lending" })
        )

        #expect(lending.children.count == 2)
    }

    @Test func protocolSectionsFallbackToAccountIdentityWhenProtocolMetadataIsMissing() throws {
        let ledger = Account(
            name: "Ledger",
            kind: .manual,
            dataSource: .manual
        )
        let exchange = Account(
            name: "Kraken",
            kind: .exchange,
            dataSource: .exchange,
            exchangeType: .kraken
        )
        let usdc = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )
        let ledgerPosition = Position(
            positionType: .lending,
            netUSDValue: 500,
            chain: .ethereum,
            account: ledger
        )
        ledgerPosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 500,
                usdValue: 500,
                asset: usdc,
                position: ledgerPosition
            )
        ]
        let exchangePosition = Position(
            positionType: .lending,
            netUSDValue: 700,
            chain: .base,
            account: exchange
        )
        exchangePosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 700,
                usdValue: 700,
                asset: usdc,
                position: exchangePosition
            )
        ]

        let lending = try #require(
            AllPositionsViewModel(positions: [ledgerPosition, exchangePosition]).sections.first(where: { $0.title == "Lending" })
        )

        #expect(lending.children.count == 2)
        #expect(Set(lending.children.compactMap(\.protocolName)) == ["Ledger", "Kraken"])
    }

    @Test func borrowRowsStayPositiveAndExposeRoleLabel() throws {
        let row = try #require(
            AllPositionsViewModel.fixture().sections
                .flatMap(\.children)
                .flatMap(\.rows)
                .first(where: { $0.role == .borrow })
        )

        #expect(row.roleLabel == "Borrow")
        #expect(row.displayAmount == 0.75)
        #expect(row.displayValue == 2_400)
        #expect(row.displayAmount > 0)
        #expect(row.displayValue > 0)
    }

    @Test func borrowRowsNormalizeNegativeSourceValues() throws {
        let account = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let eth = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )
        let borrowPosition = Position(
            positionType: .lending,
            netUSDValue: -2_400,
            chain: .ethereum,
            protocolName: "Euler",
            account: account
        )
        borrowPosition.tokens = [
            PositionToken(
                role: .borrow,
                amount: -0.75,
                usdValue: -2_400,
                asset: eth,
                position: borrowPosition
            )
        ]

        let row = try #require(
            AllPositionsViewModel(positions: [borrowPosition]).sections
                .flatMap(\.children)
                .flatMap(\.rows)
                .first
        )

        #expect(row.roleLabel == "Borrow")
        #expect(row.displayAmount == 0.75)
        #expect(row.displayValue == 2_400)
    }

    @Test func selectedProtocolFilterUpdatesTotals() {
        let viewModel = AllPositionsViewModel.fixture()

        viewModel.selectedProtocol = "Aave V3"

        #expect(viewModel.visibleUSDTotal == 3_200)
        #expect(viewModel.sections.map(\.title) == ["Idle Onchain"])
    }

    @Test func updatingPositionsClearsInvalidProtocolSelection() {
        let viewModel = AllPositionsViewModel.fixture()

        viewModel.selectedProtocol = "Euler"
        viewModel.updatePositions(
            AllPositionsViewModel.fixturePositions().filter { $0.positionType == .idle }
        )

        #expect(viewModel.selectedProtocol == nil)
        #expect(viewModel.visibleUSDTotal == 3_700)
    }

    @Test func emptyStateUsesNoPositionsCopyWhenWorkspaceIsEmpty() {
        let viewModel = AllPositionsViewModel()

        #expect(viewModel.emptyStateTitle == "No Positions")
        #expect(viewModel.emptyStateMessage == "Add a position to start building the workspace.")
    }

    @Test func emptyStateUsesNoMatchingCopyWhenFiltersHideAllPositions() {
        let viewModel = AllPositionsViewModel.fixture()

        viewModel.selectedFilter = .staking

        #expect(viewModel.sections.isEmpty)
        #expect(viewModel.emptyStateTitle == "No Matching Positions")
        #expect(viewModel.emptyStateMessage == "Adjust the sidebar filters to narrow the position workspace.")
    }

    @Test func inactiveAccountPositionsAreExcludedFromSections() {
        let viewModel = AllPositionsViewModel.fixture()

        #expect(
            viewModel.sections
                .flatMap(\.children)
                .map(\.protocolName)
                .contains("Dormant") == false
        )
    }
}

@MainActor
private extension AllPositionsViewModel {
    static func fixture() -> AllPositionsViewModel {
        AllPositionsViewModel(positions: fixturePositions())
    }

    static func fixturePositions() -> [Position] {
        let activeWallet = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let activeExchange = Account(
            name: "Kraken",
            kind: .exchange,
            dataSource: .exchange,
            exchangeType: .kraken
        )
        let inactiveWallet = Account(
            name: "Dormant Wallet",
            kind: .wallet,
            dataSource: .manual,
            isActive: false
        )

        let eth = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )
        let usdc = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )
        let btc = Asset(
            symbol: "BTC",
            name: "Bitcoin",
            coinGeckoId: "bitcoin",
            category: .major,
            isVerified: true
        )

        let idleOnchain = Position(
            positionType: .idle,
            netUSDValue: 3_200,
            chain: .ethereum,
            protocolName: "Aave V3",
            account: activeWallet
        )
        idleOnchain.tokens = [
            PositionToken(
                role: .balance,
                amount: 1,
                usdValue: 3_200,
                asset: eth,
                position: idleOnchain
            )
        ]

        let lending = Position(
            positionType: .lending,
            netUSDValue: -2_400,
            chain: .ethereum,
            protocolName: "Euler",
            healthFactor: 1.8,
            account: activeWallet
        )
        lending.tokens = [
            PositionToken(
                role: .supply,
                amount: 0.5,
                usdValue: 1_600,
                asset: usdc,
                position: lending
            ),
            PositionToken(
                role: .borrow,
                amount: 0.75,
                usdValue: 2_400,
                asset: eth,
                position: lending
            )
        ]

        let idleExchange = Position(
            positionType: .idle,
            netUSDValue: 500,
            protocolName: "Kraken",
            account: activeExchange
        )
        idleExchange.tokens = [
            PositionToken(
                role: .balance,
                amount: 500,
                usdValue: 500,
                asset: usdc,
                position: idleExchange
            )
        ]

        let dormant = Position(
            positionType: .idle,
            netUSDValue: 9_999,
            chain: .bitcoin,
            protocolName: "Dormant",
            account: inactiveWallet
        )
        dormant.tokens = [
            PositionToken(
                role: .balance,
                amount: 0.2,
                usdValue: 9_999,
                asset: btc,
                position: dormant
            )
        ]

        activeWallet.positions = [idleOnchain, lending]
        activeExchange.positions = [idleExchange]
        inactiveWallet.positions = [dormant]

        return [idleOnchain, lending, idleExchange, dormant]
    }
}
