import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>

    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]
    @State private var searchText = ""

    private var activePositions: [Position] {
        positions.filter { $0.account?.isActive == true }
    }

    private var totalValue: Decimal {
        activePositions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
    }

    private var change24h: Decimal {
        var total: Decimal = 0
        for position in activePositions {
            for token in position.tokens {
                guard
                    let asset = token.asset,
                    let coinGeckoId = asset.coinGeckoId,
                    let price = appState.prices[coinGeckoId],
                    let changePct = appState.priceChanges24h[coinGeckoId] else { continue }

                let contribution = token.amount * price * changePct
                if token.role.isPositive {
                    total += contribution
                } else if token.role.isBorrow {
                    total -= contribution
                }
            }
        }
        return total
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
                    SidebarPortfolioHeader(totalValue: totalValue, change24h: change24h)

                    DashboardSearchField(placeholder: "Search", text: $searchText)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(filteredSections) { section in
                            SidebarNavigationSection(
                                section: section,
                                selectedSection: store.sidebarSelection,
                                isSettingsSelected: store.isSettingsPresented) { item in
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
                items: SidebarLayout.footerItems,
                isSettingsSelected: store.isSettingsPresented) {
                    store.send(.settingsSelected)
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
            store.send(.settingsSelected)
        case .strategies:
            break
        }
    }
}

private struct SidebarPortfolioHeader: View {
    let totalValue: Decimal
    let change24h: Decimal

    var body: some View {
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
                Text(totalValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(spacing: 4) {
                    Text(change24h, format: .currency(code: "USD").precision(.fractionLength(0)))
                    Text("24h")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(change24h < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardSuccess)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct SidebarNavigationSection: View {
    let section: SidebarLayoutSection
    let selectedSection: SidebarSection?
    let isSettingsSelected: Bool
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
            selectedSection == section && !isSettingsSelected
        case .settings:
            isSettingsSelected
        case .strategies:
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
        if isDisabled { return PortuTheme.dashboardTertiaryText }
        return isSelected ? PortuTheme.dashboardGold : PortuTheme.dashboardSecondaryText
    }

    private var textColor: Color {
        if isDisabled { return PortuTheme.dashboardTertiaryText }
        return isSelected ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText
    }
}

private struct SidebarFooter: View {
    let items: [SidebarItem]
    let isSettingsSelected: Bool
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
                            isSelected: isSettingsSelected,
                            isDisabled: false)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                case .section, .strategies:
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
        case .strategies: "Strategies"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case let .section(section): section.systemImage
        case .strategies: "lightbulb"
        case .settings: "gearshape"
        }
    }
}
