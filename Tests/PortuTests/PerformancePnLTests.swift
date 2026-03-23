import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Performance PnL Tests")
struct PerformancePnLTests {
    @Test func pnlUsesSnapshotDeltaBetweenDays() throws {
        let bars = PerformanceViewModel.fixture().pnlBars

        #expect(bars[0].value == 250)
    }

    @Test func pnlSkipsNonConsecutiveSnapshots() {
        let calendar = Calendar(identifier: .gregorian)
        let latest = Date(timeIntervalSince1970: 1_774_137_600) // 2026-03-22T12:00:00Z
        let earliest = calendar.date(byAdding: .day, value: -3, to: latest)!
        let batchID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let viewModel = PerformanceViewModel(
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: earliest,
                    totalValue: 1_000,
                    idleValue: 200,
                    deployedValue: 800,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    totalValue: 1_500,
                    idleValue: 300,
                    deployedValue: 1_200,
                    debtValue: 0,
                    isPartial: false
                )
            ]
        )
        viewModel.selectedRange = .oneWeek

        #expect(viewModel.pnlBars.isEmpty)
    }

    @Test func pnlUsesClosingSnapshotForEachDay() {
        let calendar = Calendar(identifier: .gregorian)
        let batchID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let dayOneOpen = Date(timeIntervalSince1970: 1_773_878_400) // 2026-03-19T12:00:00Z
        let dayTwoOpen = calendar.date(byAdding: .day, value: 1, to: dayOneOpen)!
        let dayTwoClose = calendar.date(byAdding: .hour, value: 8, to: dayTwoOpen)!
        let dayThree = calendar.date(byAdding: .day, value: 2, to: dayOneOpen)!
        let viewModel = PerformanceViewModel(
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayOneOpen,
                    totalValue: 1_000,
                    idleValue: 200,
                    deployedValue: 800,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayTwoOpen,
                    totalValue: 1_500,
                    idleValue: 300,
                    deployedValue: 1_200,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayTwoClose,
                    totalValue: 1_600,
                    idleValue: 300,
                    deployedValue: 1_300,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayThree,
                    totalValue: 1_700,
                    idleValue: 350,
                    deployedValue: 1_350,
                    debtValue: 0,
                    isPartial: false
                )
            ]
        )
        viewModel.selectedRange = .oneWeek

        #expect(viewModel.pnlBars.count == 2)
        #expect(viewModel.pnlBars[0].value == 600)
        #expect(viewModel.pnlBars[1].value == 100)
    }

    @Test func pnlResumesOnceSnapshotsBecomeConsecutiveAgain() {
        let calendar = Calendar(identifier: .gregorian)
        let batchID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let dayOne = Date(timeIntervalSince1970: 1_773_878_400) // 2026-03-19T12:00:00Z
        let dayThree = calendar.date(byAdding: .day, value: 2, to: dayOne)!
        let dayFour = calendar.date(byAdding: .day, value: 3, to: dayOne)!
        let viewModel = PerformanceViewModel(
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayOne,
                    totalValue: 1_000,
                    idleValue: 200,
                    deployedValue: 800,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayThree,
                    totalValue: 1_300,
                    idleValue: 250,
                    deployedValue: 1_050,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: dayFour,
                    totalValue: 1_450,
                    idleValue: 300,
                    deployedValue: 1_150,
                    debtValue: 0,
                    isPartial: false
                )
            ]
        )
        viewModel.selectedRange = .oneWeek

        #expect(viewModel.pnlBars.count == 1)
        #expect(viewModel.pnlBars[0].value == 150)
    }

    @Test func categoryPanelUsesPeriodStartAndEndValues() throws {
        let row = try #require(PerformanceViewModel.fixture().categorySummaryRows.first)

        #expect(row.changePercent != 0)
    }

    @Test func categorySummaryRowsMarkUndefinedPercentForNewCategories() {
        let row = CategorySummaryRow(
            category: .other,
            startValue: .zero,
            endValue: 100
        )

        #expect(row.hasDefinedChangePercent == false)
    }

    @Test func assetPriceRowsMarkUndefinedPercentForNewAssets() {
        let row = AssetPriceRow(
            assetID: UUID(),
            symbol: "NEW",
            startPrice: .zero,
            endPrice: 10,
            latestValue: 100
        )

        #expect(row.hasDefinedChangePercent == false)
    }
}

@MainActor
private extension PerformanceViewModel {
    static func fixture() -> PerformanceViewModel {
        let batchID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let majorAssetID = UUID(uuidString: "11111111-1111-1111-1111-111111111101")!
        let stableAssetID = UUID(uuidString: "22222222-2222-2222-2222-222222222202")!
        let calendar = Calendar(identifier: .gregorian)
        let latest = Date(timeIntervalSince1970: 1_774_137_600) // 2026-03-22T12:00:00Z
        let middle = calendar.date(byAdding: .day, value: -1, to: latest)!
        let earliest = calendar.date(byAdding: .day, value: -2, to: latest)!

        let viewModel = PerformanceViewModel(
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: earliest,
                    totalValue: 1_000,
                    idleValue: 200,
                    deployedValue: 800,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: middle,
                    totalValue: 1_250,
                    idleValue: 250,
                    deployedValue: 1_000,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    totalValue: 1_500,
                    idleValue: 300,
                    deployedValue: 1_200,
                    debtValue: 0,
                    isPartial: false
                )
            ],
            assetSnapshots: [
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: earliest,
                    accountId: accountID,
                    assetId: majorAssetID,
                    symbol: "BTC",
                    category: .major,
                    amount: 0.05,
                    usdValue: 1_000,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: earliest,
                    accountId: accountID,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 500,
                    usdValue: 500,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: middle,
                    accountId: accountID,
                    assetId: majorAssetID,
                    symbol: "BTC",
                    category: .major,
                    amount: 0.05,
                    usdValue: 1_250,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: middle,
                    accountId: accountID,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 450,
                    usdValue: 450,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountID,
                    assetId: majorAssetID,
                    symbol: "BTC",
                    category: .major,
                    amount: 0.05,
                    usdValue: 1_500,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountID,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 400,
                    usdValue: 400,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                )
            ]
        )
        viewModel.selectedRange = .oneWeek
        return viewModel
    }
}
