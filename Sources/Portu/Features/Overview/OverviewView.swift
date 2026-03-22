import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]
    @Query private var snapshots: [PortfolioSnapshot]

    static var previewBody: String {
        let ranges = TimeRangePicker.Range.allCases.map(\.label).joined(separator: " ")
        return "Overview Sync \(ranges)"
    }

    private var viewModel: OverviewViewModel {
        OverviewViewModel(
            positions: positions,
            prices: appState.prices,
            changes24h: appState.priceChanges24h,
            snapshots: snapshots
        )
    }

    var body: some View {
        let viewModel = viewModel

        Group {
            if viewModel.positions.isEmpty {
                ContentUnavailableView {
                    Label("No Overview Data", systemImage: "chart.pie")
                } description: {
                    Text("Add an account or run a sync to populate positions.")
                } actions: {
                    Button("Add Account") {
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        OverviewHeader(viewModel: viewModel)
                        OverviewChartSection(viewModel: viewModel)
                        OverviewSummaryCards(positions: viewModel.positions)
                        OverviewTabbedTokens(viewModel: viewModel)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Overview")
    }
}
