import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

/// The Overview headline, from the portfolio read model only (#123). Before the first projection
/// build there is nothing to value, so every figure is a dash and the label carries no currency; a
/// failed build says so on the dash.
struct OverviewTopBar: View {
    let store: StoreOf<PortfolioFeature>

    var body: some View {
        let valued = store.valued
        let headline = valued?.headline
        let currencyCode = valued?.currencyCode

        VStack(alignment: .leading, spacing: 18) {
            Text(OverviewPriceDisplay.currency(headline?.total, currencyCode: currencyCode))
                .font(DashboardStyle.heroValueFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .help(OverviewPriceDisplay.unavailableHelp(valued: valued, buildError: store.buildError))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(OverviewPriceDisplay.currency(headline?.change24h, currencyCode: currencyCode))
                        .lineLimit(1)
                    Spacer()
                    Text(currencyCode.map { "\($0) change 24h" } ?? "change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: headline?.change24h ?? 0))

                HStack(spacing: 4) {
                    if let changePercentage = headline?.changePercentage {
                        Image(systemName: changePercentage >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption2)
                    }
                    Text(OverviewPriceDisplay.changePercentage(headline?.changePercentage))
                        .lineLimit(1)
                    Spacer()
                    Text("% change 24h")
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(PortuTheme.changeColor(for: headline?.changePercentage ?? 0))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}
