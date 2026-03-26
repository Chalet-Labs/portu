import SwiftData
import SwiftUI
import PortuCore

struct ExposureView: View {
    static let navigationTitle = "Exposure"

    @Query private var positions: [Position]

    private var viewModel: ExposureViewModel {
        ExposureViewModel(positions: positions)
    }

    var body: some View {
        let viewModel = viewModel

        VStack(alignment: .leading, spacing: 20) {
            ExposureSummaryCards(
                rows: viewModel.categoryRows,
                netExposureExcludingStablecoins: viewModel.netExposureExcludingStablecoins
            )

            ExposureTable(
                rows: viewModel.categoryRows,
                displayMode: .category
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(Self.navigationTitle)
    }
}
