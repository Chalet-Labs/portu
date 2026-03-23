import SwiftData
import SwiftUI
import PortuCore

struct PerformanceView: View {
    static let navigationTitle = "Performance"
    static let supportedModes: [PerformanceChartMode] = [.value, .assets]

    @Query(sort: \PortfolioSnapshot.timestamp) private var portfolioSnapshots: [PortfolioSnapshot]
    @Query(sort: \AccountSnapshot.timestamp) private var accountSnapshots: [AccountSnapshot]
    @Query(sort: \AssetSnapshot.timestamp) private var assetSnapshots: [AssetSnapshot]
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var selectedMode: PerformanceChartMode = .value
    @State private var selectedRange: PerformanceRange = .oneMonth
    @State private var selectedAccountID: UUID?

    private var viewModel: PerformanceViewModel {
        let viewModel = PerformanceViewModel(
            portfolioSnapshots: portfolioSnapshots,
            accountSnapshots: accountSnapshots,
            assetSnapshots: assetSnapshots
        )
        viewModel.selectedMode = selectedMode
        viewModel.selectedRange = selectedRange
        viewModel.selectedAccountID = normalizedSelectedAccountID
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PerformanceControls(
                    supportedModes: Self.supportedModes,
                    selectedMode: $selectedMode,
                    selectedRange: $selectedRange,
                    selectedAccountID: $selectedAccountID,
                    accounts: activeAccounts
                )

                PerformanceChartSection(
                    supportedModes: Self.supportedModes,
                    viewModel: viewModel
                )
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
}
