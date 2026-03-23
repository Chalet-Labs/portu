import SwiftUI
import Charts
import PortuCore
import PortuUI

struct PerformanceChartSection: View {
    let supportedModes: [PerformanceChartMode]
    let viewModel: PerformanceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title,
                subtitle: subtitle
            )

            if displayedMode == .value {
                if viewModel.valuePoints.isEmpty {
                    emptyState("Sync to start building performance history.")
                } else {
                    Chart(viewModel.valuePoints) { point in
                        AreaMark(
                            x: .value("Timestamp", point.date),
                            y: .value("Value", doubleValue(point.value))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Timestamp", point.date),
                            y: .value("Value", doubleValue(point.value))
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 260)
                }
            } else {
                if viewModel.assetStacks.isEmpty {
                    emptyState("Sync more asset snapshots to build category charts.")
                } else {
                    Chart {
                        ForEach(sortedCategories, id: \.self) { category in
                            ForEach(viewModel.assetStacks[category] ?? []) { point in
                                AreaMark(
                                    x: .value("Timestamp", point.date),
                                    y: .value("Value", doubleValue(point.value)),
                                    stacking: .standard
                                )
                                .foregroundStyle(by: .value("Category", category.rawValue.capitalized))
                            }
                        }
                    }
                    .frame(height: 260)
                    .chartLegend(position: .bottom)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var title: String {
        if displayedMode == .value {
            "Portfolio Value"
        } else {
            "Asset Categories"
        }
    }

    private var subtitle: String {
        if displayedMode == .value {
            "Portfolio and account snapshots over the selected range"
        } else {
            "Gross asset balances stacked by category"
        }
    }

    private var displayedMode: PerformanceChartMode {
        if supportedModes.contains(viewModel.selectedMode) {
            return viewModel.selectedMode
        }

        return .value
    }

    private var sortedCategories: [AssetCategory] {
        viewModel.assetStacks.keys.sorted { $0.rawValue < $1.rawValue }
    }

    @ViewBuilder
    private func emptyState(
        _ message: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary.opacity(0.6))
            .frame(height: 260)
            .overlay {
                Text(message)
                    .foregroundStyle(.secondary)
            }
    }

    private func doubleValue(
        _ value: Decimal
    ) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
