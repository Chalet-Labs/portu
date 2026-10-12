import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewTopBar: View {
    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]
    var sources = OverviewValuationSources()

    private var headline: OverviewHeadline {
        sources.headline(positions)
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
                    }
                    Text(OverviewPriceDisplay.changePercentage(currentHeadline.changePercentage))
                        .lineLimit(1)
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
