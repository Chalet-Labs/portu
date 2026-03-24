import SwiftData
import SwiftUI
import PortuCore
import PortuUI

struct PerformanceView: View {
    static let navigationTitle = "Performance"
    static let supportedModes: [PerformanceChartMode] = PerformanceChartMode.allCases

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnapshots: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnapshots: [AccountSnapshot]
    @Query(sort: \AssetSnapshot.timestamp) private var assetSnapshots: [AssetSnapshot]
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var selectedMode: PerformanceChartMode = .value
    @State private var selectedRange: PerformanceRange = .oneMonth
    @State private var selectedAccountID: UUID?
    @State private var enabledCategories: Set<AssetCategory> = Set(AssetCategory.allCases)

    private var viewModel: PerformanceViewModel {
        let viewModel = PerformanceViewModel(
            portfolioSnapshots: portfolioSnapshots,
            accountSnapshots: accountSnapshots,
            assetSnapshots: assetSnapshots
        )
        viewModel.selectedMode = selectedMode
        viewModel.selectedRange = selectedRange
        viewModel.selectedAccountID = normalizedSelectedAccountID
        viewModel.enabledCategories = enabledCategories
        return viewModel
    }

    private var activeAccounts: [Account] {
        accounts.filter(\.isActive)
    }

    private var activeAccountIDs: [UUID] {
        activeAccounts.map(\.id)
    }

    private var normalizedSelectedAccountID: UUID? {
        Self.normalizedSelectedAccountID(
            selectedAccountID,
            activeAccounts: activeAccounts
        )
    }

    var body: some View {
        let currentViewModel = viewModel
        let categorySummaryRows = currentViewModel.categorySummaryRows
        let assetPriceRows = currentViewModel.assetPriceRows
        let partialWarningStatus = Self.partialWarningStatus(
            partialAccountIDs: currentViewModel.partialAccountIDs,
            accounts: accounts
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PerformanceControls(
                    supportedModes: Self.supportedModes,
                    selectedMode: $selectedMode,
                    selectedRange: $selectedRange,
                    selectedAccountID: $selectedAccountID,
                    enabledCategories: $enabledCategories,
                    accounts: activeAccounts
                )

                if let partialWarningStatus {
                    HStack {
                        SyncStatusBadge(status: partialWarningStatus)
                        Spacer()
                    }
                }

                PerformanceChartSection(
                    supportedModes: Self.supportedModes,
                    viewModel: currentViewModel
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        AssetCategoriesPanel(rows: categorySummaryRows)
                        AssetPricesPanel(rows: assetPriceRows)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        AssetCategoriesPanel(rows: categorySummaryRows)
                        AssetPricesPanel(rows: assetPriceRows)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(Self.navigationTitle)
        .onAppear {
            selectedAccountID = normalizedSelectedAccountID
        }
        .onChange(of: activeAccountIDs) { _, _ in
            selectedAccountID = normalizedSelectedAccountID
        }
    }

    static func normalizedSelectedAccountID(
        _ selectedAccountID: UUID?,
        activeAccounts: [Account]
    ) -> UUID? {
        guard let selectedAccountID else {
            return nil
        }

        if activeAccounts.contains(where: { $0.id == selectedAccountID }) {
            return selectedAccountID
        }

        return nil
    }

    static func partialWarningStatus(
        partialAccountIDs: Set<UUID>,
        accounts: [Account]
    ) -> SyncStatusBadge.Status? {
        guard !partialAccountIDs.isEmpty else {
            return nil
        }

        let accountNamesByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let partialAccountNames = partialAccountIDs
            .compactMap { accountNamesByID[$0] }
            .sorted()
        let unresolvedCount = partialAccountIDs.count - partialAccountNames.count
        let unresolvedNames = Array(repeating: "Unknown account", count: unresolvedCount)

        return .completedWithErrors(failedAccounts: partialAccountNames + unresolvedNames)
    }
}
