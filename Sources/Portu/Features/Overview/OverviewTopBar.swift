// Sources/Portu/Features/Overview/OverviewTopBar.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historicalPriceChanges24h) private var historicalPriceChanges24h
    @Query private var positions: [Position]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
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

    private var totalValue: Decimal {
        activePositions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
    }

    private var change24h: Decimal {
        OverviewPriceChangeFeature.portfolioChange24h(
            tokens: TokenEntry.fromActiveTokens(activePositions.flatMap(\.tokens)),
            prices: appState.prices,
            changes24h: priceChanges24h,
            overrides: tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init),
            mappings: tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init),
            settings: dashboardSettings)
    }

    private var priceChanges24h: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedChanges24h(
            live: appState.priceChanges24h,
            historical: historicalPriceChanges24h)
    }

    private func changePct(totalValue: Decimal, change24h: Decimal) -> Decimal {
        let prev = totalValue - change24h
        guard prev != 0 else { return 0 }
        return change24h / prev
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    var body: some View {
        let currentTotalValue = totalValue
        let currentChange24h = change24h
        let currentChangePct = changePct(totalValue: currentTotalValue, change24h: currentChange24h)

        VStack(alignment: .leading, spacing: 18) {
            Text(OverviewPriceDisplay.currency(currentTotalValue))
                .font(DashboardStyle.heroValueFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(OverviewPriceDisplay.currency(currentChange24h))
                        .lineLimit(1)
                    Spacer()
                    Text("$ change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: currentChange24h))

                HStack(spacing: 4) {
                    Image(systemName: currentChangePct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(currentChangePct, format: .percent.precision(.fractionLength(2)))
                        .lineLimit(1)
                    Spacer()
                    Text("% change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: currentChangePct))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}
