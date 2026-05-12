import ComposableArchitecture
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case tokens
    case categories
    case apiKeys
    case debug

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "General"
        case .tokens: "Tokens"
        case .categories: "Categories"
        case .apiKeys: "API Keys"
        case .debug: "Debug"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Price refresh preferences for portfolio data."
        case .tokens: "Manual pricing, low-value visibility, and token overrides."
        case .categories: "Category symbol rules for app-wide portfolio categories."
        case .apiKeys: "Provider credentials and optional custom RPC endpoints."
        case .debug: "Local debug server controls for development builds."
        }
    }

    static func visibleTabs(debugEnabled: Bool) -> [SettingsTab] {
        debugEnabled ? [.general, .tokens, .categories, .apiKeys, .debug] : [.general, .tokens, .categories, .apiKeys]
    }

    static func filter(_ tabs: [SettingsTab], query: String) -> [SettingsTab] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return tabs }

        return tabs.filter { tab in
            tab.title.lowercased().contains(normalizedQuery)
                || tab.subtitle.lowercased().contains(normalizedQuery)
        }
    }
}

enum SettingsMetrics {
    static let minimumWidth: CGFloat = 720
    static let minimumHeight: CGFloat = 560
    static let sidebarWidth: CGFloat = 208
    static let pageTitleSize: CGFloat = 22
    static let sectionTitleSize: CGFloat = 15
    static let rowTitleSize: CGFloat = 14
    static let sidebarRowTitleSize: CGFloat = 13
    static let sidebarHeaderTitle = "Settings"
    static let sidebarHeaderTitleSize: CGFloat = 30
    static let compactControlHeight: CGFloat = 34
    static let compactInputHeight: CGFloat = 34
    static let showsBackNavigation = false
}

struct SettingsView: View {
    let store: StoreOf<AppFeature>
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText = ""

    private var tabs: [SettingsTab] {
        SettingsTab.visibleTabs(debugEnabled: Self.debugEnabled)
    }

    private var filteredTabs: [SettingsTab] {
        SettingsTab.filter(tabs, query: searchText)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                tabs: filteredTabs,
                selectedTab: $selectedTab,
                searchText: $searchText)

            Rectangle()
                .fill(SettingsDesign.separator)
                .frame(width: 1)

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: SettingsMetrics.minimumWidth,
            maxWidth: .infinity,
            minHeight: SettingsMetrics.minimumHeight,
            maxHeight: .infinity)
        .background(SettingsDesign.contentBackground)
        .onChange(of: filteredTabs) { _, newTabs in
            guard !newTabs.isEmpty, !newTabs.contains(selectedTab) else { return }
            selectedTab = newTabs[0]
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab(store: store)
        case .tokens:
            TokenSettingsTab()
        case .categories:
            CategorySettingsTab()
        case .apiKeys:
            APIKeysSettingsTab()
        case .debug:
            #if DEBUG
                DebugSettingsTab()
            #else
                SettingsPage(tab: .debug) {
                    SettingsSectionCard(
                        title: "Debug unavailable",
                        subtitle: "Debug settings are only available in development builds.",
                        icon: .debugServer) {
                            EmptyView()
                        }
                }
            #endif
        }
    }

    private static var debugEnabled: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }
}

private struct SettingsSidebar: View {
    let tabs: [SettingsTab]
    @Binding var selectedTab: SettingsTab
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSidebarHeader()

            SettingsSearchField(text: $searchText)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        SettingsSidebarRow(
                            tab: tab,
                            isSelected: selectedTab == tab)
                    }
                    .buttonStyle(.plain)
                }

                if tabs.isEmpty {
                    Text("No settings found")
                        .font(.callout)
                        .foregroundStyle(SettingsDesign.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }

            Spacer(minLength: 24)
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 16)
        .frame(width: SettingsMetrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(SettingsDesign.sidebarBackground)
    }

    private var topPadding: CGFloat {
        12
    }
}

private struct SettingsSidebarHeader: View {
    var body: some View {
        Text(SettingsMetrics.sidebarHeaderTitle)
            .font(.system(size: SettingsMetrics.sidebarHeaderTitleSize, weight: .bold))
            .foregroundStyle(SettingsDesign.primaryText)
            .lineLimit(1)
            .frame(height: 50, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
    }
}

private struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SettingsDesign.secondaryText)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Search")
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                TextField("Search", text: $text, prompt: Text(""))
                    .textFieldStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.primaryText)
                    .accessibilityLabel("Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(SettingsDesign.sidebarSearchBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }
}

private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyphTile(tab: tab, isSelected: isSelected)
                .frame(width: 28, height: 28)

            Text(tab.title)
                .font(.system(size: SettingsMetrics.sidebarRowTitleSize, weight: .semibold))
                .foregroundStyle(isSelected ? SettingsDesign.accentPrimary : SettingsDesign.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(isSelected ? SettingsDesign.sidebarSelection : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .stroke(isSelected ? SettingsDesign.accentPrimary.opacity(0.34) : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous))
    }
}

private struct GeneralSettingsTab: View {
    let store: StoreOf<AppFeature>

    @AppStorage(PricePollingSettings.refreshIntervalKey)
    private var refreshInterval = PricePollingSettings.defaultRefreshIntervalSeconds
    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    var body: some View {
        SettingsPage(tab: .general) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Price Updates",
                    subtitle: "Choose how often Portu refreshes token pricing.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Refresh interval")
                                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                                    .foregroundStyle(SettingsDesign.primaryText)
                                Text("Default: 30 seconds")
                                    .font(.footnote)
                                    .foregroundStyle(SettingsDesign.secondaryText)
                            }

                            RefreshIntervalControl(selection: $refreshInterval)
                        }
                    }

                SettingsSectionCard(
                    title: HistoricalPriceBackfillSettings.sectionTitle,
                    subtitle: "Cache CoinGecko daily prices separately from Portu snapshots.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(HistoricalPriceBackfillSettings.useBackfillTitle, isOn: $historicalBackfillEnabled)
                                .toggleStyle(SettingsSwitchToggleStyle())

                            HStack(spacing: 10) {
                                Button(HistoricalPriceBackfillSettings.backfillButtonTitle) {
                                    store.send(.historicalPriceBackfill(.backfillButtonTapped))
                                }
                                .buttonStyle(.plain)
                                .settingsPrimaryButton(isDisabled: store.historicalPriceBackfill.status.isRunning)
                                .disabled(store.historicalPriceBackfill.status.isRunning)

                                Button(HistoricalPriceBackfillSettings.clearCacheButtonTitle) {
                                    store.send(.historicalPriceBackfill(.clearCacheButtonTapped))
                                }
                                .buttonStyle(.plain)
                                .settingsPrimaryButton(isDisabled: false)
                            }

                            HistoricalBackfillStatusText(status: store.historicalPriceBackfill.status)
                        }
                    }

                SettingsInfoCard(
                    title: "Auto-saved",
                    message: "This setting is stored locally with AppStorage and applies across Portu views.")
            }
        }
    }
}

private struct HistoricalBackfillStatusText: View {
    let status: HistoricalBackfillStatus

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(SettingsDesign.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        switch status {
        case .idle:
            "No historical backfill run in this session."
        case .running:
            "Fetching historical prices from CoinGecko..."
        case let .succeeded(result):
            "Fetched \(result.fetchedAssets) assets, inserted \(result.insertedPoints), "
                + "updated \(result.updatedPoints), skipped \(result.skippedAssets)."
        case let .failed(message):
            "Backfill failed: \(message)"
        }
    }
}

private enum RefreshIntervalOption: Double, CaseIterable, Identifiable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Double {
        rawValue
    }

    var title: String {
        switch self {
        case .fifteenSeconds: "15 seconds"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        }
    }
}

private struct RefreshIntervalControl: View {
    @Binding var selection: Double

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RefreshIntervalOption.allCases) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    Text(option.title)
                        .font(.footnote.weight(isSelected(option) ? .bold : .regular))
                        .foregroundStyle(isSelected(option) ? SettingsDesign.primaryText : SettingsDesign.secondaryText)
                        .frame(width: 84, height: 30)
                        .background(selectedBackground(for: option))
                }
                .buttonStyle(.plain)

                if option != .fiveMinutes {
                    Rectangle()
                        .fill(SettingsDesign.separator)
                        .frame(width: 1, height: 24)
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }

    private func isSelected(_ option: RefreshIntervalOption) -> Bool {
        selection == option.rawValue
    }

    @ViewBuilder
    private func selectedBackground(for option: RefreshIntervalOption) -> some View {
        if isSelected(option) {
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(SettingsDesign.accentPrimary.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                        .stroke(SettingsDesign.accentPrimary.opacity(0.62), lineWidth: 1))
        }
    }
}
