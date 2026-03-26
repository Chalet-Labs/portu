import Foundation
import Testing
import PortuCore
import PortuNetwork
@testable import Portu

@MainActor
@Suite("Asset Detail Chart Tests")
struct AssetDetailChartTests {
    @Test func chartModeSwitchingUsesMatchingSeries() throws {
        let viewModel = AssetDetailViewModel.fixtureBorrowOnly()

        #expect(viewModel.selectedSeries == viewModel.priceSeries)

        viewModel.selectedMode = .value
        #expect(viewModel.selectedSeries == viewModel.valueSeries)

        viewModel.selectedMode = .amount
        #expect(viewModel.selectedSeries == viewModel.amountSeries)
    }

    @Test func priceModeDoesNotInventSnapshotDerivedPrices() {
        let viewModel = AssetDetailViewModel.fixtureBorrowOnly()

        #expect(viewModel.priceSeries.isEmpty)
        #expect(viewModel.priceSummaryLabel == "Price unavailable")
    }

    @Test func borrowOnlyAssetsDisplayDebtLabelInValueMode() {
        let viewModel = AssetDetailViewModel.fixtureBorrowOnly()

        #expect(viewModel.valueSummaryLabel == "Debt: $500.00")
    }

    @Test func borrowOnlyAssetsDisplayBorrowedLabelInAmountMode() {
        let viewModel = AssetDetailViewModel.fixtureBorrowOnly()

        #expect(viewModel.amountSummaryLabel == "Borrowed: 2")
    }

    @Test func selectedSummaryLabelTracksChartMode() {
        let viewModel = AssetDetailViewModel.fixtureBorrowOnly()

        #expect(viewModel.selectedSummaryLabel == "Price unavailable")

        viewModel.selectedMode = .value
        #expect(viewModel.selectedSummaryLabel == "Debt: $500.00")

        viewModel.selectedMode = .amount
        #expect(viewModel.selectedSummaryLabel == "Borrowed: 2")
    }

    @Test func historicalPriceSeriesDrivesPriceModeSummary() throws {
        let timestamp = Date(timeIntervalSince1970: 1_774_137_600)
        let viewModel = AssetDetailViewModel.fixtureBorrowOnly(
            historicalPrices: [
                HistoricalPricePoint(date: timestamp, price: 250)
            ]
        )
        let point = try #require(viewModel.priceSeries.first)

        #expect(point.value == 250)
        #expect(viewModel.selectedSummaryLabel == "Price: $250.00")
    }

    @Test func comparisonOverlayNormalizesSeriesFromFirstPoint() {
        let start = Date(timeIntervalSince1970: 1_774_137_600)
        let end = start.addingTimeInterval(86_400)
        let normalized = AssetPriceChart.normalizedOverlaySeries(from: [
            PerformancePoint(date: start, value: 50, usesAccountSnapshot: false),
            PerformancePoint(date: end, value: 100, usesAccountSnapshot: false),
        ])

        #expect(normalized.map(\.value) == [100, 200])
    }
}

@MainActor
private extension AssetDetailViewModel {
    static func fixtureBorrowOnly(
        historicalPrices: [HistoricalPricePoint] = []
    ) -> AssetDetailViewModel {
        let account = Account(
            name: "Borrow Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        account.id = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!

        let asset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true
        )
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!

        let borrowPosition = Position(
            positionType: .lending,
            netUSDValue: -500,
            chain: .arbitrum,
            protocolName: "Aave V3",
            account: account
        )
        borrowPosition.tokens = [
            PositionToken(
                role: .borrow,
                amount: 2,
                usdValue: 500,
                asset: asset,
                position: borrowPosition
            )
        ]

        let batchID = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!
        let timestamp = Date(timeIntervalSince1970: 1_774_137_600)

        return AssetDetailViewModel(
            assetID: asset.id,
            positions: [borrowPosition],
            assetSnapshots: [
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: timestamp,
                    accountId: account.id,
                    assetId: asset.id,
                    symbol: "ETH",
                    category: .major,
                    amount: 0,
                    usdValue: 0,
                    borrowAmount: 2,
                    borrowUsdValue: 500
                )
            ],
            historicalPrices: historicalPrices,
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: timestamp,
                    totalValue: 1_000,
                    idleValue: 0,
                    deployedValue: 1_000,
                    debtValue: 500,
                    isPartial: false
                )
            ]
        )
    }
}
