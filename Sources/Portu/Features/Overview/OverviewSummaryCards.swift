import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

/// Idle, Deployed and Debt from the portfolio read model (#124). Before the first build the rows
/// are known but nothing is valued, so each shows a dash.
struct OverviewSummaryCards: View {
    let store: StoreOf<PortfolioFeature>

    var body: some View {
        let overview = store.overview
        let isValued = overview.summaryCards != nil

        HStack(alignment: .top, spacing: PortuTheme.dashboardContentSpacing) {
            ForEach(overview.summaryCards ?? OverviewSummaryCardsFeature.unvalued) { card in
                summaryCard(card, isValued: isValued, currencyCode: overview.currencyCode)
            }
        }
        .help(isValued ? "" : OverviewPriceDisplay.unavailableHelp(buildError: store.buildError))
    }

    private func summaryCard(_ card: OverviewSummaryCard, isValued: Bool, currencyCode: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            ForEach(card.rows) { item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(OverviewPriceDisplay.currency(isValued ? item.value : nil, currencyCode: currencyCode))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(PortuTheme.dashboardText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .dashboardCard()
    }
}

enum OverviewSummaryCardsFeature {
    /// The cards' titles and row labels before anything is valued; the majors row is generic.
    static let unvalued = cards(
        ValuationContext(
            inputs: [],
            overrides: [],
            mappings: [],
            settings: .defaults,
            usdToDisplayRate: 1,
            prices: ValuationPriceInputs()),
        categories: [])
}
