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

            switch displayedMode {
            case .value:
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
            case .assets:
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
            case .pnl:
                if viewModel.pnlBars.isEmpty {
                    emptyState("Sync multiple snapshots to build daily profit and loss.")
                } else {
                    Chart(viewModel.pnlBars) { bar in
                        BarMark(
                            x: .value("Timestamp", bar.date),
                            y: .value("PnL", doubleValue(bar.value))
                        )
                        .foregroundStyle(bar.value < .zero ? Color.red : Color.green)
                    }
                    .frame(height: 260)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var title: String {
        switch displayedMode {
        case .value:
            "Portfolio Value"
        case .assets:
            "Asset Categories"
        case .pnl:
            "Profit and Loss"
        }
    }

    private var subtitle: String {
        switch displayedMode {
        case .value:
            "Portfolio and account snapshots over the selected range"
        case .assets:
            "Gross asset balances stacked by category"
        case .pnl:
            "Daily mark-to-market deltas from the selected snapshot series"
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
