import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("All Assets ViewModel Tests")
struct AllAssetsViewModelTests {
    @Test func assetRowsNetBorrowAgainstSupply() throws {
        let viewModel = AllAssetsViewModel.fixture()
        let eth = try #require(viewModel.assetRows.first(where: { $0.symbol == "ETH" }))

        #expect(eth.netAmount == 1.25)
        #expect(eth.value == 4_000)
        #expect(eth.value < eth.grossValue)
    }

    @Test func networksTabBucketsNilChainsAsOffChainCustodial() throws {
        let viewModel = AllAssetsViewModel.fixture()
        let row = try #require(viewModel.networkRows.first(where: { $0.title == "Off-chain / Custodial" }))

        #expect(row.positionCount == 1)
        #expect(row.usdBalance == 500)
    }

    @Test func assetRowsFilterBySearchAcrossSymbolAndName() {
        let viewModel = AllAssetsViewModel.fixture()
        viewModel.searchText = "staked"

        #expect(viewModel.assetRows.map(\.symbol) == ["stETH"])
    }

    @Test func inactiveAccountPositionsAreExcludedFromAggregates() {
        let viewModel = AllAssetsViewModel.fixture()

        #expect(viewModel.assetRows.contains(where: { $0.symbol == "BTC" }) == false)
    }

    @Test func positionsWithoutAccountsAreExcludedFromAggregates() {
        let asset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )

        let orphanedPosition = Position(
            positionType: .idle,
            netUSDValue: 3_200,
            chain: .ethereum,
            protocolName: "Wallet"
        )
        orphanedPosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 1,
                usdValue: 3_200,
                asset: asset,
                position: orphanedPosition
            )
        ]

        let viewModel = AllAssetsViewModel(
            positions: [orphanedPosition],
            livePrices: ["ethereum": 3_200]
        )

        #expect(viewModel.assetRows.isEmpty)
        #expect(viewModel.networkRows.isEmpty)
    }
}

@MainActor
private extension AllAssetsViewModel {
    static func fixture() -> AllAssetsViewModel {
        let wallet = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        let exchange = Account(
            name: "Kraken",
            kind: .exchange,
            dataSource: .exchange,
            exchangeType: .kraken
        )
        let inactive = Account(
            name: "Dormant",
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
        let stakedETH = Asset(
            symbol: "stETH",
            name: "Staked Ether",
            coinGeckoId: "lido-staked-ether",
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
        let bitcoin = Asset(
            symbol: "BTC",
            name: "Bitcoin",
            coinGeckoId: "bitcoin",
            category: .major,
            isVerified: true
        )

        let walletBalance = Position(
            positionType: .idle,
            netUSDValue: 6_400,
            chain: .ethereum,
            protocolName: "Wallet",
            account: wallet
        )
        walletBalance.tokens = [
            PositionToken(
                role: .balance,
                amount: 2,
                usdValue: 6_400,
                asset: eth,
                position: walletBalance
            )
        ]

        let borrowPosition = Position(
            positionType: .lending,
            netUSDValue: -2_400,
            chain: .ethereum,
            protocolName: "Aave V3",
            account: wallet
        )
        borrowPosition.tokens = [
            PositionToken(
                role: .borrow,
                amount: 0.75,
                usdValue: 2_400,
                asset: eth,
                position: borrowPosition
            )
        ]

        let stakedPosition = Position(
            positionType: .staking,
            netUSDValue: 4_800,
            chain: .ethereum,
            protocolName: "Lido",
            account: wallet
        )
        stakedPosition.tokens = [
            PositionToken(
                role: .stake,
                amount: 1.5,
                usdValue: 4_800,
                asset: stakedETH,
                position: stakedPosition
            )
        ]

        let exchangePosition = Position(
            positionType: .idle,
            netUSDValue: 500,
            protocolName: "Kraken",
            account: exchange
        )
        exchangePosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 500,
                usdValue: 500,
                asset: usdc,
                position: exchangePosition
            )
        ]

        let inactivePosition = Position(
            positionType: .idle,
            netUSDValue: 1_000,
            chain: .bitcoin,
            protocolName: "Wallet",
            account: inactive
        )
        inactivePosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 0.02,
                usdValue: 1_000,
                asset: bitcoin,
                position: inactivePosition
            )
        ]

        wallet.positions = [walletBalance, borrowPosition, stakedPosition]
        exchange.positions = [exchangePosition]
        inactive.positions = [inactivePosition]

        return AllAssetsViewModel(
            positions: wallet.positions + exchange.positions + inactive.positions,
            livePrices: [
                "ethereum": 3_200,
                "lido-staked-ether": 3_200,
                "usd-coin": 1,
                "bitcoin": 50_000
            ]
        )
    }
}
