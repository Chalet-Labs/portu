import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewPositionTabs: View {
    @Environment(AppState.self) private var appState
    @Query private var allPositions: [Position]
    var sources = OverviewValuationSources()
    var categories = OverviewCategorySource()

    @State private var selectedTab: OverviewPositionTab = .keyChanges

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

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
        let data = tabData
        let currencyCode = appState.selectedCurrency.displayCode

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

    // MARK: - Context

    /// Built fresh on every body evaluation, including tab clicks.
    ///
    /// Deliberately not memoized (issue #98 residual, audited 2026-09-02):
    /// the rebuild — the valuation inputs, the USD price inputs, small-table
    /// maps and resolver construction — is dominated by the per-tab projection that
    /// a tab click runs anyway. A staleness-free `@State` cache key is buildable
    /// today (`PortfolioCategoryResolver` is `Equatable`, with snapshot-based stored
    /// properties), but building and comparing the key on every body would re-pay
    /// most of the rebuild it avoids. If this ever shows up in Instruments, memoize
    /// keyed on those resolver snapshots.
    private var tabData: OverviewPositionTabData {
        sources.positionTab(selectedTab, positions: positions, categoryResolver: categories.resolver)
    }
}
