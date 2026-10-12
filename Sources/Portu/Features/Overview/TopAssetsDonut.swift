import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct TopAssetsDonut: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState
    @Query private var tokens: [PositionToken]
    var sources = OverviewValuationSources()
    var categories = OverviewCategorySource()

    @State private var selectedMode: TopAssetMode = .assets

    private var topAssets: OverviewTopAssets {
        sources.topAssets(
            selectedMode,
            tokens: tokens,
            categoryResolver: categories.resolver)
    }

    var body: some View {
        let current = topAssets

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                modeButton(.assets)
                modeButton(.category)
                Spacer()

                Button(TopAssetsDonutText.seeAllButtonTitle) {
                    store.send(.sectionSelected(.allAssets))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(PortuTheme.dashboardGold)
                .lineLimit(1)
                .buttonStyle(.plain)
            }

            if current.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    chart(current)
                        .frame(width: 162, height: 162)

                    legend(current)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func chart(_ topAssets: OverviewTopAssets) -> some View {
        Chart {
            ForEach(topAssets.chartSlices) { slice in
                SectorMark(
                    angle: .value("Value", slice.value),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.4)
                    .foregroundStyle(chartColor(index: slice.colorIndex))
            }

            if let hiddenValue = topAssets.hiddenChartValue {
                SectorMark(
                    angle: .value("Value", hiddenValue),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.4)
                    .foregroundStyle(Self.hiddenColor)
            }
        }
        .chartLegend(.hidden)
    }

    private func legend(_ topAssets: OverviewTopAssets) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(topAssets.slices) { slice in
                HStack(spacing: 7) {
                    legendMarker(for: slice)

                    Text(slice.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PortuTheme.dashboardText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    legendPercent(slice.displayPercent)
                }
            }

            if let hidden = topAssets.hidden {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Self.hiddenColor)
                        .frame(width: 7, height: 7)

                    Text(OverviewPriceDisplay.hiddenBalancesLine(
                        hidden,
                        basis: .gross,
                        currencyCode: appState.selectedCurrency.displayCode))
                        .font(.system(size: 11))
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.middle)

                    legendPercent(topAssets.hiddenDisplayPercent)
                }
            }
        }
    }

    private func legendPercent(_ percent: Int?) -> some View {
        Text(percent.map { "\($0)%" } ?? "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
            .lineLimit(1)
    }

    private static let hiddenColor = PortuTheme.dashboardTertiaryText

    private func chartColor(index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.360, green: 0.610, blue: 0.700),
            Color(red: 0.930, green: 0.800, blue: 0.280),
            Color(red: 0.400, green: 0.800, blue: 0.730),
            Color(red: 0.760, green: 0.300, blue: 0.250),
            Color(red: 0.830, green: 0.600, blue: 0.230),
            Color(red: 0.900, green: 0.900, blue: 0.840),
            Color(red: 0.480, green: 0.420, blue: 0.720),
            Color(red: 0.650, green: 0.450, blue: 0.320)
        ]
        return colors[index % colors.count]
    }

    private func modeButton(_ mode: TopAssetMode) -> some View {
        Button {
            selectedMode = mode
        } label: {
            Text(mode.title)
                .font(.system(size: 14, weight: selectedMode == mode ? .semibold : .regular))
                .foregroundStyle(selectedMode == mode ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedMode == mode ? PortuTheme.dashboardGold : .clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func legendMarker(for slice: OverviewAssetSlice) -> some View {
        if selectedMode == .assets, slice.logoURL != nil {
            AssetLogoView(symbol: slice.label, logoURL: slice.logoURL)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(chartColor(index: slice.colorIndex), lineWidth: 1))
        } else {
            Circle()
                .fill(chartColor(index: slice.colorIndex))
                .frame(width: 7, height: 7)
        }
    }
}

enum TopAssetsDonutText {
    static let seeAllButtonTitle = "See all →"
}

enum TopAssetMode {
    case assets
    case category

    var title: String {
        switch self {
        case .assets: "Top Assets"
        case .category: "By Category"
        }
    }
}
