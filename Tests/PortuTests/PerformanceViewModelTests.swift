import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Performance ViewModel Tests")
struct PerformanceViewModelTests {
    @Test func performanceChartModeDefaultsToValue() {
        #expect(PerformanceViewModel().selectedMode == .value)
    }

    @Test func performanceControlsExposeAllChartModes() {
        #expect(PerformanceView.supportedModes == PerformanceChartMode.allCases)
    }

    @Test func performanceViewKeepsActiveAccountSelection() {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let account = Account(name: "Primary", kind: .wallet, dataSource: .zapper)
        account.id = accountID

        #expect(
            PerformanceView.normalizedSelectedAccountID(
                accountID,
                activeAccounts: [account]
            ) == accountID
        )
    }

    @Test func performanceViewClearsStaleAccountSelection() {
        let activeAccount = Account(name: "Primary", kind: .wallet, dataSource: .zapper)
        activeAccount.id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let staleSelection = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!

        #expect(
            PerformanceView.normalizedSelectedAccountID(
                staleSelection,
                activeAccounts: [activeAccount]
            ) == nil
        )
    }

    @Test func contentViewRoutesPerformanceSectionToPerformanceWorkspace() {
        #expect(ContentView.destination(for: .performance) == .performance)
    }

    @Test func valueModeUsesAccountSnapshotsWhenAccountIsSelected() {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let viewModel = PerformanceViewModel.fixture(selectedAccountID: accountID)

        #expect(viewModel.valuePoints.map(\.value) == [1_000, 1_200])
        #expect(viewModel.valuePoints.allSatisfy { $0.usesAccountSnapshot })
    }

    @Test func assetModeStacksGrossUsdByCategory() throws {
        let category = try #require(PerformanceViewModel.fixture().assetStacks[.major]?.first)

        #expect(category.value == 1_500)
        #expect(category.usesAccountSnapshot == false)
    }

    @Test func selectedRangeExcludesSnapshotsOutsideTheWindow() {
        let viewModel = PerformanceViewModel.fixture(selectedRange: .oneWeek)

        #expect(viewModel.valuePoints.count == 1)
        #expect(viewModel.valuePoints.map(\.value) == [3_500])
    }
}

@MainActor
private extension PerformanceViewModel {
    static func fixture(
        selectedAccountID: UUID? = nil,
        selectedRange: PerformanceRange = .oneMonth
    ) -> PerformanceViewModel {
        let batchID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let accountA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let accountB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let majorAssetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let stableAssetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let calendar = Calendar(identifier: .gregorian)
        let latest = Date(timeIntervalSince1970: 1_774_137_600) // 2026-03-22T12:00:00Z
        let mid = calendar.date(byAdding: .day, value: -17, to: latest)!
        let old = calendar.date(byAdding: .day, value: -66, to: latest)!

        let viewModel = PerformanceViewModel(
            portfolioSnapshots: [
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: old,
                    totalValue: 2_000,
                    idleValue: 500,
                    deployedValue: 1_500,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: mid,
                    totalValue: 3_000,
                    idleValue: 900,
                    deployedValue: 2_100,
                    debtValue: 0,
                    isPartial: false
                ),
                PortfolioSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    totalValue: 3_500,
                    idleValue: 1_100,
                    deployedValue: 2_400,
                    debtValue: 0,
                    isPartial: false
                )
            ],
            accountSnapshots: [
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: old,
                    accountId: accountA,
                    totalValue: 800,
                    isFresh: true
                ),
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: mid,
                    accountId: accountA,
                    totalValue: 1_000,
                    isFresh: true
                ),
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountA,
                    totalValue: 1_200,
                    isFresh: true
                ),
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: old,
                    accountId: accountB,
                    totalValue: 1_200,
                    isFresh: true
                ),
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: mid,
                    accountId: accountB,
                    totalValue: 2_000,
                    isFresh: true
                ),
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountB,
                    totalValue: 2_300,
                    isFresh: true
                )
            ],
            assetSnapshots: [
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: old,
                    accountId: accountA,
                    assetId: majorAssetID,
                    symbol: "ETH",
                    category: .major,
                    amount: 1,
                    usdValue: 400,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: old,
                    accountId: accountA,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 200,
                    usdValue: 200,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: old,
                    accountId: accountB,
                    assetId: majorAssetID,
                    symbol: "ETH",
                    category: .major,
                    amount: 0.2,
                    usdValue: 600,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: mid,
                    accountId: accountA,
                    assetId: majorAssetID,
                    symbol: "ETH",
                    category: .major,
                    amount: 0.3,
                    usdValue: 700,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: mid,
                    accountId: accountA,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 300,
                    usdValue: 300,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: mid,
                    accountId: accountB,
                    assetId: majorAssetID,
                    symbol: "ETH",
                    category: .major,
                    amount: 0.25,
                    usdValue: 800,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountA,
                    assetId: majorAssetID,
                    symbol: "ETH",
                    category: .major,
                    amount: 0.35,
                    usdValue: 900,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountA,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 250,
                    usdValue: 250,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountB,
                    assetId: majorAssetID,
                    symbol: "ETH",
                    category: .major,
                    amount: 0.1,
                    usdValue: 300,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                ),
                AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: latest,
                    accountId: accountB,
                    assetId: stableAssetID,
                    symbol: "USDC",
                    category: .stablecoin,
                    amount: 100,
                    usdValue: 100,
                    borrowAmount: 0,
                    borrowUsdValue: 0
                )
            ]
        )
        viewModel.selectedAccountID = selectedAccountID
        viewModel.selectedRange = selectedRange
        return viewModel
    }
}
