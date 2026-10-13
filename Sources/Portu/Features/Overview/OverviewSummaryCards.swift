import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewSummaryCards: View {
    @Environment(AppState.self) private var appState
    @Query private var allPositions: [Position]
    var sources = OverviewValuationSources()
    var categories = OverviewCategorySource()

    private var cards: [OverviewSummaryCard] {
        sources.summaryCards(
            allPositions,
            categoryResolver: categories.resolver)
    }

    private var currencyCode: String {
        appState.selectedCurrency.displayCode
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortuTheme.dashboardContentSpacing) {
            ForEach(cards) { card in
                summaryCard(title: card.title, items: card.rows)
            }
        }
    }

    private func summaryCard(title: String, items: [OverviewSummaryCardRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            ForEach(items) { item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(OverviewPriceDisplay.currency(item.value, currencyCode: currencyCode))
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

enum OverviewSummaryCardsFeature {}
