import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

/// The position tabs from the portfolio read model (#124): every tab is valued with each
/// revaluation, so a tab click only re-renders.
struct OverviewPositionTabs: View {
    let store: StoreOf<PortfolioFeature>

    @State private var selectedTab: OverviewPositionTab = .keyChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(OverviewPositionTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 12) {
                tabContent
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        let overview = store.overview

        if let data = overview.positionTabs?[selectedTab], let currencyCode = overview.currencyCode {
            if data.showsEmptyState {
                emptyState(selectedTab.emptyMessage)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(data.groups) { group in
                        OverviewPositionGroupCard(group: group, currencyCode: currencyCode)
                    }

                    // Groups with no visible row have no card; their rows end the tab in one line (S3).
                    if let hidden = data.hidden {
                        OverviewHiddenBalancesLine(
                            text: OverviewPriceDisplay.hiddenBalancesLine(hidden, basis: data.basis, currencyCode: currencyCode))
                            .overviewPositionPanel()
                    }
                }
            }
        } else {
            emptyState(OverviewPriceDisplay.unvaluedPlaceholder)
                .help(OverviewPriceDisplay.unavailableHelp(buildError: store.buildError))
        }
    }

    private func tabButton(_ tab: OverviewPositionTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedTab == tab ? PortuTheme.dashboardGold : .clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardTertiaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }
}
