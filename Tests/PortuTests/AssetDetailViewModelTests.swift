import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Asset Detail ViewModel Tests")
struct AssetDetailViewModelTests {
    @Test func assetDetailUsesNetUsdValueForValueMode() throws {
        let point = try #require(AssetDetailViewModel.fixture().valueSeries.first)

        #expect(point.value == -500)
    }

    @Test func assetDetailUsesNetAmountForAmountMode() throws {
        let point = try #require(AssetDetailViewModel.fixture().amountSeries.first)

        #expect(point.value == -2)
    }

    @Test func chainSummariesUsePositionChainNotAssetUpsertChain() throws {
        let row = try #require(AssetDetailViewModel.fixture().networkRows.first)

        #expect(row.networkName == "Arbitrum")
        #expect(row.usdValue == 1_500)
    }

    @Test func positionRowsProjectAccountPlatformAndContext() throws {
        let row = try #require(AssetDetailViewModel.fixture().positionRows.first)

        #expect(row.accountName == "Main Wallet")
        #expect(row.platformName == "Aave V3")
        #expect(row.contextLabel == "Lending")
        #expect(row.networkName == "Arbitrum")
        #expect(row.amount == 1.5)
        #expect(row.usdBalance == 1_500)
    }

    @Test func holdingsSummaryTracksAccountCountAmountAndUsdValue() {
        let viewModel = AssetDetailViewModel.fixture()

        #expect(viewModel.accountCount == 2)
        #expect(viewModel.totalAmount == -0.5)
        #expect(viewModel.totalUSDValue == 1_000)
    }

    @Test func partialHistoryTracksPartialPortfolioBatches() {
        #expect(AssetDetailViewModel.fixture().containsPartialHistory)
    }

    @Test func stakingRowsUseStakedContextLabel() throws {
        let account = Account(
            name: "Staking Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let asset = Asset(
            symbol: "SOL",
            name: "Solana",
            coinGeckoId: "solana",
            category: .major,
            isVerified: true
        )

        let position = Position(
            positionType: .staking,
            netUSDValue: 500,
            chain: .solana,
            protocolName: "Native Staking",
            account: account
        )
        position.tokens = [
            PositionToken(
                role: .stake,
                amount: 10,
                usdValue: 500,
                asset: asset,
                position: position
            )
        ]

        let row = try #require(
            AssetDetailViewModel(
                assetID: asset.id,
                positions: [position]
            ).positionRows.first
        )

        #expect(row.contextLabel == "Staked")
    }

    @Test func positionRowsBreakTiesByPlatformNameBeforeIdentifier() {
        let account = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let asset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )

        let aave = AssetDetailViewModel.makePosition(
            type: .lending,
            value: 1_000,
            chain: .arbitrum,
            protocolName: "Aave V3",
            account: account,
            role: .supply,
            amount: 1,
            usdValue: 1_000,
            asset: asset
        )
        let lido = AssetDetailViewModel.makePosition(
            type: .lending,
            value: 1_000,
            chain: .arbitrum,
            protocolName: "Lido",
            account: account,
            role: .supply,
            amount: 1,
            usdValue: 1_000,
            asset: asset
        )

        let rows = AssetDetailViewModel(
            assetID: asset.id,
            positions: [lido, aave]
        ).positionRows

        #expect(rows.map(\.platformName) == ["Aave V3", "Lido"])
    }

    @Test func networkRowsSortByAbsoluteExposureDescending() {
        let account = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let asset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )

        let long = AssetDetailViewModel.makePosition(
            type: .lending,
            value: 500,
            chain: .arbitrum,
            protocolName: "Aave V3",
            account: account,
            role: .supply,
            amount: 0.5,
            usdValue: 500,
            asset: asset
        )
        let short = AssetDetailViewModel.makePosition(
            type: .lending,
            value: -800,
            chain: .base,
            protocolName: "Aave V3",
            account: account,
            role: .borrow,
            amount: 0.8,
            usdValue: 800,
            asset: asset
        )

        let rows = AssetDetailViewModel(
            assetID: asset.id,
            positions: [long, short]
        ).networkRows

        #expect(rows.map(\.networkName) == ["Base", "Arbitrum"])
    }
}

@MainActor
private extension AssetDetailViewModel {
    static func fixture() -> AssetDetailViewModel {
        let primaryAccount = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        primaryAccount.id = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!

        let secondaryAccount = Account(
            name: "Margin Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        secondaryAccount.id = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

        let archivedAccount = Account(
            name: "Archived Wallet",
            kind: .wallet,
            dataSource: .manual,
            isActive: false
        )

        let ethereum = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            upsertChain: .ethereum,
            category: .major,
            isVerified: true
        )
        ethereum.id = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

        let bitcoin = Asset(
            symbol: "BTC",
            name: "Bitcoin",
            coinGeckoId: "bitcoin",
            category: .major,
            isVerified: true
        )
        bitcoin.id = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!

        let arbitrumSupply = Position(
            positionType: .lending,
            netUSDValue: 1_500,
            chain: .arbitrum,
            protocolName: "Aave V3",
            account: primaryAccount
        )
        arbitrumSupply.tokens = [
            PositionToken(
                role: .supply,
                amount: 1.5,
                usdValue: 1_500,
                asset: ethereum,
                position: arbitrumSupply
            )
        ]

        let baseBorrow = Position(
            positionType: .lending,
            netUSDValue: -500,
            chain: .base,
            protocolName: "Aave V3",
            account: secondaryAccount
        )
        baseBorrow.tokens = [
            PositionToken(
                role: .borrow,
                amount: 2,
                usdValue: 500,
                asset: ethereum,
                position: baseBorrow
            )
        ]

        let archivedEthereumPosition = Position(
            positionType: .idle,
            netUSDValue: 900,
            chain: .polygon,
            protocolName: "Wallet",
            account: archivedAccount
        )
        archivedEthereumPosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 0.3,
                usdValue: 900,
                asset: ethereum,
                position: archivedEthereumPosition
            )
        ]

        let unrelatedBitcoinPosition = Position(
            positionType: .idle,
            netUSDValue: 2_000,
            chain: .ethereum,
            protocolName: "Wallet",
            account: primaryAccount
        )
        unrelatedBitcoinPosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 0.05,
                usdValue: 2_000,
                asset: bitcoin,
                position: unrelatedBitcoinPosition
            )
        ]

        let startBatchID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let endBatchID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        let start = Date(timeIntervalSince1970: 1_774_137_600) // 2026-03-22T12:00:00Z
        let end = Date(timeIntervalSince1970: 1_774_224_000) // 2026-03-23T12:00:00Z

        return AssetDetailViewModel(
            assetID: ethereum.id,
            positions: [
                arbitrumSupply,
                baseBorrow,
                archivedEthereumPosition,
                unrelatedBitcoinPosition
            ],
            assetSnapshots: [
                AssetSnapshot(
                    syncBatchId: startBatchID,
                    timestamp: start,
                    accountId: primaryAccount.id,
                    assetId: ethereum.id,
                    symbol: "ETH",
                    category: .major,
                    amount: 1,
                    usdValue: 1_000,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: startBatchID,
                    timestamp: start.addingTimeInterval(60),
                    accountId: secondaryAccount.id,
                    assetId: ethereum.id,
                    symbol: "ETH",
                    category: .major,
                    amount: 0,
                    usdValue: 0,
                    borrowAmount: 3,
                    borrowUsdValue: 1_500
                ),
                AssetSnapshot(
                    syncBatchId: endBatchID,
                    timestamp: end,
                    accountId: primaryAccount.id,
                    assetId: ethereum.id,
                    symbol: "ETH",
                    category: .major,
                    amount: 2,
                    usdValue: 2_200,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: endBatchID,
                    timestamp: end.addingTimeInterval(60),
                    accountId: secondaryAccount.id,
                    assetId: ethereum.id,
                    symbol: "ETH",
                    category: .major,
                    amount: 0,
                    usdValue: 0,
                    borrowAmount: 1,
                    borrowUsdValue: 700
                ),
                AssetSnapshot(
                    syncBatchId: startBatchID,
                    timestamp: start.addingTimeInterval(120),
                    accountId: archivedAccount.id,
                    assetId: ethereum.id,
                    symbol: "ETH",
                    category: .major,
                    amount: 0.3,
                    usdValue: 900,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: startBatchID,
                    timestamp: start,
                    accountId: primaryAccount.id,
                    assetId: bitcoin.id,
                    symbol: "BTC",
                    category: .major,
                    amount: 0.05,
                    usdValue: 2_000,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                )
            ],
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: startBatchID,
                    timestamp: start.addingTimeInterval(120),
                    totalValue: 2_000,
                    idleValue: 500,
                    deployedValue: 1_500,
                    debtValue: 0,
                    isPartial: true
                ),
                PortfolioSnapshot(
                    syncBatchId: endBatchID,
                    timestamp: end.addingTimeInterval(120),
                    totalValue: 2_200,
                    idleValue: 500,
                    deployedValue: 1_700,
                    debtValue: 0,
                    isPartial: false
                )
            ]
        )
    }

    static func makePosition(
        type: PositionType,
        value: Decimal,
        chain: Chain?,
        protocolName: String,
        account: Account,
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        asset: Asset
    ) -> Position {
        let position = Position(
            positionType: type,
            netUSDValue: value,
            chain: chain,
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
