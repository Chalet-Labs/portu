import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historicalPriceChanges24h) private var historicalPriceChanges24h
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    @Environment(\.historicalMarketPrices) private var historicalMarketPrices
    @Query private var positions: [Position]
    @Query(sort: [SortDescriptor(\TokenPricingOverride.updatedAt, order: .reverse)])
    private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    /// Only positions from active accounts
    private var activePositions: [Position] {
        positions.filter { $0.account?.isActive == true }
    }

    private var headline: OverviewHeadline {
        OverviewFeature.headline(OverviewValuationContext(
            inputs: ValuationInput.activeAccounts(activePositions.flatMap(\.tokens)),
            overrides: tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init),
            mappings: tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init),
            settings: dashboardSettings,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: OverviewPriceInputs(
                livePricesUSD: appState.livePricesUSD,
                liveChanges24h: appState.priceChanges24h,
                historical: historicalMarketPrices,
                liveDisplayPrices: appState.prices,
                historicalDisplayPrices: historicalDisplayPrices,
                historicalChanges24h: historicalPriceChanges24h)))
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var currencyCode: String {
        appState.selectedCurrency.displayCode
    }

    var body: some View {
        let currentHeadline = headline

        VStack(alignment: .leading, spacing: 18) {
            Text(OverviewPriceDisplay.currency(currentHeadline.total, currencyCode: currencyCode))
                .font(DashboardStyle.heroValueFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(OverviewPriceDisplay.currency(currentHeadline.change24h, currencyCode: currencyCode))
                        .lineLimit(1)
                    Spacer()
                    Text("\(currencyCode) change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: currentHeadline.change24h))

                HStack(spacing: 4) {
                    if let changePercentage = currentHeadline.changePercentage {
                        Image(systemName: changePercentage >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption2)
                        Text(changePercentage, format: .percent.precision(.fractionLength(2)))
                            .lineLimit(1)
                    } else {
                        Text("—")
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("% change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: currentHeadline.changePercentage ?? 0))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}
