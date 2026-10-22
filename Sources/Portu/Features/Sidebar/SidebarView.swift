import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>

    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""

    init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    private var filteredSections: [SidebarLayoutSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SidebarLayout.navigationSections }

        return SidebarLayout.navigationSections.compactMap { section in
            let items = section.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
            guard !items.isEmpty else { return nil }
            return SidebarLayoutSection(title: section.title, items: items, isDisabled: section.isDisabled)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SidebarPortfolioHeader(store: store.scope(state: \.portfolio, action: \.portfolio))

                    DashboardSearchField(placeholder: "Search", text: $searchText)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(filteredSections) { section in
                            SidebarNavigationSection(
                                section: section,
                                selectedSection: store.selectedSection) { item in
                                    select(item)
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            SidebarFooter(
                items: SidebarLayout.footerItems) {
                    openSettings()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PortuTheme.dashboardSidebarBackground)
    }

    private func select(_ item: SidebarItem) {
        switch item {
        case let .section(section):
            store.send(.sectionSelected(section))
        case .settings:
            openSettings()
        }
    }
}

/// The portfolio headline, from the portfolio read model only (#123): no query, no app storage and no
/// `AppState`, so a navigation click or a save that changes no valued figure leaves it alone. Before
/// the first projection build every figure is a dash; a failed build says so on the dash.
struct SidebarPortfolioHeader: View {
    let store: StoreOf<PortfolioFeature>

    var body: some View {
        let valued = store.valued
        let headline = valued?.headline
        let currencyCode = valued?.currencyCode

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 0.910, green: 0.850, blue: 0.680))
                Text("P")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(PortuTheme.dashboardBackground)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(OverviewPriceDisplay.currency(headline?.total, currencyCode: currencyCode))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .help(OverviewPriceDisplay.unavailableHelp(valued: valued, buildError: store.buildError))
                Group {
                    HStack(spacing: 4) {
                        Text(OverviewPriceDisplay.currency(headline?.change24h, currencyCode: currencyCode))
                        Text("24h")
                    }
                    .foregroundStyle(changeColor(headline?.change24h))

                    Text(OverviewPriceDisplay.changePercentage(headline?.changePercentage))
                        .foregroundStyle(percentageColor(headline?.changePercentage))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 4)
    }

    private func changeColor(_ change: Decimal?) -> Color {
        guard let change else { return PortuTheme.dashboardTertiaryText }
        return change < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardSuccess
    }

    private func percentageColor(_ percentage: Decimal?) -> Color {
        guard let percentage else { return PortuTheme.dashboardTertiaryText }
        return percentage < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardSuccess
    }
}

private struct SidebarNavigationSection: View {
    let section: SidebarLayoutSection
    let selectedSection: SidebarSection
    let select: (SidebarItem) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = section.title {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
                    .padding(.horizontal, 8)
            }

            ForEach(section.items) { item in
                Button {
                    select(item)
                } label: {
                    SidebarNavigationRow(
                        item: item,
                        isSelected: isSelected(item),
                        isDisabled: section.isDisabled)
                }
                .buttonStyle(.plain)
                .disabled(section.isDisabled)
            }
        }
    }

    private func isSelected(_ item: SidebarItem) -> Bool {
        switch item {
        case let .section(section):
            selectedSection == section
        case .settings:
            false
        }
    }
}

private struct SidebarNavigationRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
                .foregroundStyle(iconColor)

            Text(item.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? PortuTheme.dashboardMutedPanelBackground : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isSelected ? PortuTheme.dashboardMutedStroke : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var iconColor: Color {
        if isDisabled {
            return PortuTheme.dashboardTertiaryText
        }
        return isSelected ? PortuTheme.dashboardGold : PortuTheme.dashboardSecondaryText
    }

    private var textColor: Color {
        if isDisabled {
            return PortuTheme.dashboardTertiaryText
        }
        return isSelected ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText
    }
}

private struct SidebarFooter: View {
    let items: [SidebarItem]
    let settingsAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)

            ForEach(items) { item in
                switch item {
                case .settings:
                    Button {
                        settingsAction()
                    } label: {
                        SidebarNavigationRow(
                            item: item,
                            isSelected: false,
                            isDisabled: false)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                case .section:
                    EmptyView()
                }
            }
        }
        .background(PortuTheme.dashboardSidebarBackground)
    }
}

private extension SidebarItem {
    var title: String {
        switch self {
        case let .section(section): section.title
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case let .section(section): section.systemImage
        case .settings: "gearshape"
        }
    }
}
