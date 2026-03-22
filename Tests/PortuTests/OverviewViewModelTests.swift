import Foundation
import Testing
import PortuCore
import PortuUI
@testable import Portu

@MainActor
@Suite("Overview ViewModel Tests")
struct OverviewViewModelTests {
    @Test func overviewViewModelComputesTotalAnd24hChange() throws {
        let viewModel = OverviewViewModel.fixture(
            prices: ["ethereum": 3200],
            changes24h: ["ethereum": 4.5]
        )

        #expect(viewModel.totalValue == 6400)
        #expect(viewModel.absoluteChange24h == 288)
    }

    @Test func overviewViewModelUsesCanonicalPositionTotals() {
        let viewModel = OverviewViewModel.fixture(
            prices: ["ethereum": 4_000],
            changes24h: ["ethereum": 4.5]
        )

        #expect(viewModel.totalValue == 6_400)
    }

    @Test func borrowRowsRemainPositiveButAreTaggedBorrow() throws {
        let row = try #require(OverviewViewModel.fixture().borrowingRows.first)

        #expect(row.roleLabel == "Borrow")
        #expect(row.displayValue > 0)
    }

    @Test func overviewViewModelUsesSyncFallbackPriceWhenLivePriceMissing() throws {
        let row = try #require(OverviewViewModel.fixture().rows(for: .idleMajors).first)

        #expect(row.displayPrice == 3_200)
        #expect(row.displayValue == 3_200)
        #expect(row.priceSource == .syncFallback)
    }

    @Test func borrowingTabIncludesSupplyAndBorrowRows() {
        let rows = OverviewViewModel.borrowingFixture().rows(for: .borrowing)

        #expect(rows.map(\.roleLabel).contains("Supply"))
        #expect(rows.map(\.roleLabel).contains("Borrow"))
    }

    @Test func overviewViewModelExcludesPositionsWithoutActiveAccounts() {
        let viewModel = OverviewViewModel.activeOnlyFixture()

        #expect(viewModel.totalValue == 3_200)
    }

    @Test func topAssetsKeepDistinctEntriesForSharedSymbols() {
        let viewModel = OverviewViewModel.sharedSymbolFixture()

        #expect(viewModel.topAssets.count == 2)
    }

    @Test func topAssetSharesAreNormalizedAgainstVisibleSlices() throws {
        let slice = try #require(OverviewViewModel.borrowingFixture().topAssets.first)

        #expect(slice.shareOfPortfolio == 100)
    }

    @Test func overviewViewRendersSyncActionAndTimeRanges() {
        let body = OverviewView.previewBody

        #expect(body.contains("Sync"))
        #expect(body.contains("1m"))
    }

    @Test func overviewSummaryCardsExposeGroupedBreakdowns() {
        let positions = OverviewViewModel.fixture().positions

        #expect(
            OverviewSummaryCards.idleBreakdown(for: positions).map(\.title)
                == ["Stablecoins & Fiat", "Majors", "Tokens & Memecoins"]
        )
        #expect(
            OverviewSummaryCards.deployedBreakdown(for: positions).map(\.title)
                == ["Lending", "Staked", "Yield"]
        )
    }

    @Test func borrowingGroupsSplitSameProtocolAcrossChains() {
        let rows = OverviewViewModel.duplicateProtocolBorrowingFixture().rows(for: .borrowing)
        let groups = OverviewTabbedTokens.makeBorrowingGroups(from: rows)

        #expect(groups.count == 2)
        #expect(groups.map(\.chainLabel).contains("Ethereum"))
        #expect(groups.map(\.chainLabel).contains("Solana"))
    }

    @Test func overviewHeaderUsesNeutralPresentationForZeroChange() {
        let presentation = OverviewHeader.changePresentation(for: .zero)

        #expect(presentation.iconName == "minus")
        #expect(presentation.prefix == "")
    }

    @Test func syncStatusBadgeHighlightsCompletedWithErrors() {
        let badge = SyncStatusBadge(status: .completedWithErrors(failedAccounts: ["Kraken"]))

        #expect(badge.tint == PortuTheme.warning)
    }
}

@MainActor
private extension OverviewViewModel {
    static func fixture(
        prices: [String: Decimal] = [:],
        changes24h: [String: Decimal] = [:]
    ) -> OverviewViewModel {
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

        let idlePosition = Position(
            positionType: .idle,
            netUSDValue: 3_200,
            chain: .ethereum,
            protocolName: "Wallet",
            account: account
        )
        idlePosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 1,
                usdValue: 3_200,
                asset: asset,
                position: idlePosition
            )
        ]

        let stakedPosition = Position(
            positionType: .staking,
            netUSDValue: 6_400,
            chain: .ethereum,
            protocolName: "Staking",
            account: account
        )
        stakedPosition.tokens = [
            PositionToken(
                role: .stake,
                amount: 2,
                usdValue: 6_400,
                asset: asset,
                position: stakedPosition
            )
        ]

        let borrowPosition = Position(
            positionType: .lending,
            netUSDValue: -3_200,
            chain: .ethereum,
            protocolName: "Aave",
            healthFactor: 1.8,
            account: account
        )
        borrowPosition.tokens = [
            PositionToken(
                role: .borrow,
                amount: 1,
                usdValue: 3_200,
                asset: asset,
                position: borrowPosition
            )
        ]

        account.positions = [idlePosition, stakedPosition, borrowPosition]

        return OverviewViewModel(
            positions: account.positions,
            prices: prices,
            changes24h: changes24h
        )
    }

    static func borrowingFixture() -> OverviewViewModel {
        let account = Account(
            name: "Margin",
            kind: .wallet,
            dataSource: .manual
        )
        let supplyAsset = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )
        let borrowAsset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )

        let lendingPosition = Position(
            positionType: .lending,
            netUSDValue: 1_800,
            chain: .ethereum,
            protocolName: "Aave",
            healthFactor: 1.8,
            account: account
        )
        lendingPosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 5_000,
                usdValue: 5_000,
                asset: supplyAsset,
                position: lendingPosition
            ),
            PositionToken(
                role: .borrow,
                amount: 1,
                usdValue: 3_200,
                asset: borrowAsset,
                position: lendingPosition
            )
        ]

        account.positions = [lendingPosition]

        return OverviewViewModel(
            positions: account.positions,
            prices: [
                "usd-coin": 1,
                "ethereum": 3_200
            ],
            changes24h: [
                "usd-coin": 0,
                "ethereum": 4.5
            ]
        )
    }

    static func activeOnlyFixture() -> OverviewViewModel {
        let activeAccount = Account(
            name: "Active",
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

        let activePosition = Position(
            positionType: .idle,
            netUSDValue: 3_200,
            chain: .ethereum,
            protocolName: "Wallet",
            account: activeAccount
        )
        activePosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 1,
                usdValue: 3_200,
                asset: asset,
                position: activePosition
            )
        ]

        let orphanPosition = Position(
            positionType: .idle,
            netUSDValue: 9_999,
            chain: .ethereum,
            protocolName: "Wallet"
        )
        orphanPosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 3,
                usdValue: 9_999,
                asset: asset,
                position: orphanPosition
            )
        ]

        activeAccount.positions = [activePosition]

        return OverviewViewModel(
            positions: [activePosition, orphanPosition],
            prices: ["ethereum": 3_200],
            changes24h: [:]
        )
    }

    static func sharedSymbolFixture() -> OverviewViewModel {
        let account = Account(
            name: "Shared Symbol",
            kind: .wallet,
            dataSource: .manual
        )
        let majorUsdc = Asset(
            symbol: "USD",
            name: "Major USD",
            coinGeckoId: "major-usd",
            category: .major,
            isVerified: true
        )
        let stableUsdc = Asset(
            symbol: "USD",
            name: "Stable USD",
            coinGeckoId: "stable-usd",
            category: .stablecoin,
            isVerified: true
        )

        let firstPosition = Position(
            positionType: .idle,
            netUSDValue: 100,
            protocolName: "Wallet",
            account: account
        )
        firstPosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 100,
                usdValue: 100,
                asset: majorUsdc,
                position: firstPosition
            )
        ]

        let secondPosition = Position(
            positionType: .idle,
            netUSDValue: 250,
            protocolName: "Wallet",
            account: account
        )
        secondPosition.tokens = [
            PositionToken(
                role: .balance,
                amount: 250,
                usdValue: 250,
                asset: stableUsdc,
                position: secondPosition
            )
        ]

        account.positions = [firstPosition, secondPosition]

        return OverviewViewModel(
            positions: account.positions,
            prices: [
                "major-usd": 1,
                "stable-usd": 1
            ],
            changes24h: [:]
        )
    }

    static func duplicateProtocolBorrowingFixture() -> OverviewViewModel {
        let ethereumAccount = Account(
            name: "ETH Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let solanaAccount = Account(
            name: "SOL Wallet",
            kind: .wallet,
            dataSource: .manual
        )
        let usdAsset = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true
        )
        let ethAsset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )
        let solAsset = Asset(
            symbol: "SOL",
            name: "Solana",
            coinGeckoId: "solana",
            category: .major,
            isVerified: true
        )

        let ethereumPosition = Position(
            positionType: .lending,
            netUSDValue: 1_800,
            chain: .ethereum,
            protocolName: "Aave",
            healthFactor: 1.9,
            account: ethereumAccount
        )
        ethereumPosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 5_000,
                usdValue: 5_000,
                asset: usdAsset,
                position: ethereumPosition
            ),
            PositionToken(
                role: .borrow,
                amount: 1,
                usdValue: 3_200,
                asset: ethAsset,
                position: ethereumPosition
            )
        ]

        let solanaPosition = Position(
            positionType: .lending,
            netUSDValue: 80,
            chain: .solana,
            protocolName: "Aave",
            healthFactor: 2.3,
            account: solanaAccount
        )
        solanaPosition.tokens = [
            PositionToken(
                role: .supply,
                amount: 200,
                usdValue: 200,
                asset: usdAsset,
                position: solanaPosition
            ),
            PositionToken(
                role: .borrow,
                amount: 1,
                usdValue: 120,
                asset: solAsset,
                position: solanaPosition
            )
        ]

        ethereumAccount.positions = [ethereumPosition]
        solanaAccount.positions = [solanaPosition]

        return OverviewViewModel(
            positions: [ethereumPosition, solanaPosition],
            prices: [
                "usd-coin": 1,
                "ethereum": 3_200,
                "solana": 120
            ],
            changes24h: [:]
        )
    }
}
