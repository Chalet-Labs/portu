import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Exposure ViewModel Tests")
struct ExposureViewModelTests {
    @Test func exposureDisplayModeDefaultsToCategory() {
        #expect(ExposureViewModel().displayMode == .category)
    }

    @Test func exposureSeparatesAssetsAndLiabilities() throws {
        let row = try #require(
            ExposureViewModel.fixture().categoryRows.first(where: { $0.name == "Major" })
        )

        #expect(row.spotAssets == 10_000)
        #expect(row.liabilities == 3_000)
        #expect(row.spotNet == 7_000)
        #expect(row.netExposure == 7_000)
    }

    @Test func netExposureExcludesStablecoins() {
        #expect(ExposureViewModel.fixture().netExposureExcludingStablecoins == 7_000)
    }

    @Test func exposureIgnoresInactiveAccounts() {
        let viewModel = ExposureViewModel.fixture()

        #expect(viewModel.categoryRows.contains(where: { $0.name == "Privacy" }) == false)
    }

    @Test func assetRowsNetSupplyAgainstBorrowWithStableIdentity() throws {
        let ethAssetID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let row = try #require(
            ExposureViewModel.fixture().assetRows.first(where: { $0.assetID == ethAssetID })
        )

        #expect(row.assetSymbol == "ETH")
        #expect(row.spotAssets == 10_000)
        #expect(row.liabilities == 3_000)
        #expect(row.spotNet == 7_000)
        #expect(row.netExposure == 7_000)
    }

    @Test func assetRowsExcludeInactiveAccounts() {
        let viewModel = ExposureViewModel.fixture()

        #expect(viewModel.assetRows.contains(where: { $0.assetSymbol == "XMR" }) == false)
    }

    @Test func zeroExposureRowsBreakTiesBySpotNetBeforeName() {
        let viewModel = ExposureViewModel.zeroExposureTieFixture()

        #expect(viewModel.categoryRows.map(\.name) == ["Stablecoin", "Major"])
    }

    @Test func spotPositiveRolesAccumulateAcrossSupplyStakeAndLPToken() throws {
        let solAssetID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        let row = try #require(
            ExposureViewModel.positiveRoleFixture().assetRows.first(where: { $0.assetID == solAssetID })
        )

        #expect(row.assetSymbol == "SOL")
        #expect(row.spotAssets == 600)
        #expect(row.liabilities == .zero)
        #expect(row.spotNet == 600)
    }
}

@MainActor
private extension ExposureViewModel {
    static func fixture() -> ExposureViewModel {
        let wallet = Account(
            name: "Core Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        let inactive = Account(
            name: "Archived Wallet",
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
        eth.id = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let usdc = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )
        usdc.id = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let xmr = Asset(
            symbol: "XMR",
            name: "Monero",
            coinGeckoId: "monero",
            category: .privacy,
            isVerified: true
        )
        xmr.id = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!

        let majorBalance = Position(
            positionType: .idle,
            netUSDValue: 10_000,
            chain: .ethereum,
            protocolName: "Wallet",
            account: wallet
        )
        majorBalance.tokens = [
            PositionToken(
                role: .balance,
                amount: 3,
                usdValue: 10_000,
                asset: eth,
                position: majorBalance
            )
        ]

        let majorBorrow = Position(
            positionType: .lending,
            netUSDValue: -3_000,
            chain: .ethereum,
            protocolName: "Aave V3",
            account: wallet
        )
        majorBorrow.tokens = [
            PositionToken(
                role: .borrow,
                amount: 1,
                usdValue: 3_000,
                asset: eth,
                position: majorBorrow
            )
        ]

        let stableBalance = Position(
            positionType: .idle,
            netUSDValue: 2_000,
            chain: .ethereum,
            protocolName: "Wallet",
            account: wallet
        )
        stableBalance.tokens = [
            PositionToken(
                role: .balance,
                amount: 2_000,
                usdValue: 2_000,
                asset: usdc,
                position: stableBalance
            )
        ]

        let inactivePrivacyBalance = Position(
            positionType: .idle,
            netUSDValue: 500,
            chain: .ethereum,
            protocolName: "Wallet",
            account: inactive
        )
        inactivePrivacyBalance.tokens = [
            PositionToken(
                role: .balance,
                amount: 5,
                usdValue: 500,
                asset: xmr,
                position: inactivePrivacyBalance
            )
        ]

        return ExposureViewModel(
            positions: [
                majorBalance,
                majorBorrow,
                stableBalance,
                inactivePrivacyBalance
            ]
        )
    }

    static func zeroExposureTieFixture() -> ExposureViewModel {
        let wallet = Account(
            name: "Tie Wallet",
            kind: .wallet,
            dataSource: .zapper
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

        return ExposureViewModel(
            positions: [
                position(
                    type: .idle,
                    netUSDValue: 1_000,
                    protocolName: "Wallet",
                    account: wallet,
                    role: .balance,
                    amount: 1,
                    usdValue: 1_000,
                    asset: eth
                ),
                position(
                    type: .lending,
                    netUSDValue: -1_000,
                    protocolName: "Aave V3",
                    account: wallet,
                    role: .borrow,
                    amount: 1,
                    usdValue: 1_000,
                    asset: eth
                ),
                position(
                    type: .idle,
                    netUSDValue: 2_000,
                    protocolName: "Wallet",
                    account: wallet,
                    role: .balance,
                    amount: 2_000,
                    usdValue: 2_000,
                    asset: usdc
                )
            ]
        )
    }

    static func positiveRoleFixture() -> ExposureViewModel {
        let wallet = Account(
            name: "Role Wallet",
            kind: .wallet,
            dataSource: .zapper
        )

        let sol = Asset(
            symbol: "SOL",
            name: "Solana",
            coinGeckoId: "solana",
            category: .major,
            isVerified: true
        )
        sol.id = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!

        return ExposureViewModel(
            positions: [
                position(
                    type: .lending,
                    netUSDValue: 100,
                    protocolName: "Marginfi",
                    account: wallet,
                    role: .supply,
                    amount: 10,
                    usdValue: 100,
                    asset: sol
                ),
                position(
                    type: .staking,
                    netUSDValue: 200,
                    protocolName: "Marinade",
                    account: wallet,
                    role: .stake,
                    amount: 20,
                    usdValue: 200,
                    asset: sol
                ),
                position(
                    type: .liquidityPool,
                    netUSDValue: 300,
                    protocolName: "Orca",
                    account: wallet,
                    role: .lpToken,
                    amount: 30,
                    usdValue: 300,
                    asset: sol
                )
            ]
        )
    }

    private static func position(
        type: PositionType,
        netUSDValue: Decimal,
        protocolName: String,
        account: Account,
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        asset: Asset
    ) -> Position {
        let position = Position(
            positionType: type,
            netUSDValue: netUSDValue,
            chain: .ethereum,
            protocolName: protocolName,
            account: account
        )
        position.tokens = [
            PositionToken(
                role: role,
                amount: amount,
                usdValue: usdValue,
                asset: asset,
                position: position
            )
        ]

        return position
    }
}
