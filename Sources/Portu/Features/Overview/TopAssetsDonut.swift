import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct TopAssetsDonut: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    @Environment(\.historicalMarketPrices) private var historicalMarketPrices
    @Query private var tokens: [PositionToken]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    @State private var selectedMode: TopAssetMode = .assets

    private var slices: [OverviewAssetSlice] {
        OverviewFeature.topAssets(
            selectedMode,
            context: OverviewValuationContext(
                inputs: ValuationInput.activeAccounts(
                    tokens,
                    categoryResolver: PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)),
                overrides: tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init),
                mappings: tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init),
                settings: dashboardSettings,
                usdToDisplayRate: appState.currentUSDToDisplayRate,
                prices: OverviewPriceInputs(
                    livePricesUSD: appState.livePricesUSD,
                    historical: historicalMarketPrices,
                    liveDisplayPrices: appState.prices,
                    historicalDisplayPrices: historicalDisplayPrices)))
            .slices
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    var body: some View {
        let currentSlices = slices

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

            if currentSlices.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(currentSlices) { slice in
                        SectorMark(
                            angle: .value("Value", slice.value),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.4)
                            .foregroundStyle(chartColor(index: slice.colorIndex))
                    }
                    .chartLegend(.hidden)
                    .frame(width: 162, height: 162)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(currentSlices) { slice in
                            HStack(spacing: 7) {
                                legendMarker(for: slice)

                                Text(slice.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PortuTheme.dashboardText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text("\(slice.displayPercent)%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

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
