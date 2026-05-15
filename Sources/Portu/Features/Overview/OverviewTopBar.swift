// Sources/Portu/Features/Overview/OverviewTopBar.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]

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
            changes24h: appState.priceChanges24h,
            overrides: tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init),
            mappings: tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init))
    }

    private var changePct: Decimal {
        let prev = totalValue - change24h
        guard prev != 0 else { return 0 }
        return change24h / prev
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OverviewPriceDisplay.currency(totalValue))
                .font(DashboardStyle.heroValueFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(OverviewPriceDisplay.currency(change24h))
                        .lineLimit(1)
                    Spacer()
                    Text("$ change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: change24h))

                HStack(spacing: 4) {
                    Image(systemName: changePct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(changePct, format: .percent.precision(.fractionLength(2)))
                        .lineLimit(1)
                    Spacer()
                    Text("% change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: changePct))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}
