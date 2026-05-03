import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case apiKeys
    case debug

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "General"
        case .apiKeys: "API Keys"
        case .debug: "Debug"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Price refresh preferences for portfolio data."
        case .apiKeys: "Provider credentials and optional custom RPC endpoints."
        case .debug: "Local debug server controls for development builds."
        }
    }

    var sidebarGlyph: String {
        switch self {
        case .general: "G"
        case .apiKeys: "K"
        case .debug: "D"
        }
    }

    static func visibleTabs(debugEnabled: Bool) -> [SettingsTab] {
        debugEnabled ? [.general, .apiKeys, .debug] : [.general, .apiKeys]
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
    static let sidebarWidth: CGFloat = 226
    static let pageTitleSize: CGFloat = 32
    static let sectionTitleSize: CGFloat = 20
    static let rowTitleSize: CGFloat = 18
    static let sidebarRowTitleSize: CGFloat = 15
    static let compactControlHeight: CGFloat = 40
    static let compactInputHeight: CGFloat = 40
    static let showsBackNavigation = false
}

struct SettingsView: View {
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
            GeneralSettingsTab()
        case .apiKeys:
            APIKeysSettingsTab()
        case .debug:
            #if DEBUG
                DebugSettingsTab()
            #else
                SettingsPage(tab: .debug) {
                    SettingsSectionCard(
                        title: "Debug unavailable",
                        subtitle: "Debug settings are only available in development builds.") {
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
        VStack(alignment: .leading, spacing: 20) {
            SettingsBrandHeader()

            SettingsSearchField(text: $searchText)

            VStack(alignment: .leading, spacing: 8) {
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
        42
    }
}

private struct SettingsBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsDesign.logoBackground)
                Text("P")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(SettingsDesign.logoForeground)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Portu")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text("Settings")
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.secondaryText)
            }
        }
        .padding(.horizontal, 8)
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
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(SettingsDesign.sidebarSearchBackground))
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
                .foregroundStyle(isSelected ? SettingsDesign.accentBlue : SettingsDesign.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? SettingsDesign.sidebarSelection : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage(PricePollingSettings.refreshIntervalKey)
    private var refreshInterval = PricePollingSettings.defaultRefreshIntervalSeconds

    var body: some View {
        SettingsPage(tab: .general) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSectionCard(
                    title: "Price Updates",
                    subtitle: "Choose how often Portu refreshes token pricing.") {
                        HStack(alignment: .top, spacing: 14) {
                            SettingsGlyphTile(tab: .general)
                                .frame(width: 32, height: 32)

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
                    }

                SettingsInfoCard(
                    title: "Auto-saved",
                    message: "This setting is stored locally with AppStorage and applies across Portu views.")
            }
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
                        .frame(width: 84, height: 34)
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.930, green: 0.950, blue: 0.980)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }

    private func isSelected(_ option: RefreshIntervalOption) -> Bool {
        selection == option.rawValue
    }

    @ViewBuilder
    private func selectedBackground(for option: RefreshIntervalOption) -> some View {
        if isSelected(option) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
    }
}
