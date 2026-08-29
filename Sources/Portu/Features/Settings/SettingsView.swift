import ComposableArchitecture
import PortuCore
import SwiftUI

struct SettingsView: View {
    let store: StoreOf<AppFeature>
    let secretStore: any SecretStore
    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText = ""

    init(
        store: StoreOf<AppFeature>,
        secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        self.store = store
        self.secretStore = secretStore
    }

    private var allVisibleTabs: [SettingsTab] {
        SettingsTab.visibleTabs(debugEnabled: Self.debugEnabled)
    }

    private var filteredTabs: [SettingsTab] {
        SettingsTab.filter(allVisibleTabs, query: searchText)
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            if let tab = selectedTab {
                selectedContent(for: tab)
            } else {
                ContentUnavailableView(
                    "Select a Setting",
                    systemImage: "gearshape",
                    description: Text("Choose a category from the sidebar."))
            }
        }
        .frame(
            minWidth: SettingsMetrics.minimumWidth,
            idealWidth: SettingsMetrics.idealWidth,
            maxWidth: .infinity,
            minHeight: SettingsMetrics.minimumHeight,
            idealHeight: SettingsMetrics.idealHeight,
            maxHeight: .infinity)
        .onChange(of: filteredTabs) { _, newTabs in
            guard !newTabs.isEmpty else { return }
            if let current = selectedTab, !newTabs.contains(current) {
                selectedTab = newTabs[0]
            } else if selectedTab == nil {
                selectedTab = newTabs[0]
            }
        }
    }

    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            if searchText.isEmpty {
                ForEach(SettingsGroup.allCases) { group in
                    let groupTabs = allVisibleTabs.filter { $0.group == group }
                    if !groupTabs.isEmpty {
                        Section(group.rawValue) {
                            ForEach(groupTabs) { tab in
                                Label {
                                    Text(tab.title)
                                } icon: {
                                    Image(systemName: tab.systemImage)
                                }
                                .tag(tab as SettingsTab?)
                            }
                        }
                    }
                }
            } else {
                ForEach(filteredTabs) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: tab.systemImage)
                    }
                    .tag(tab as SettingsTab?)
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
    }

    @ViewBuilder
    private func selectedContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(store: store)
        case .updates:
            UpdatesSettingsView(store: store)
        case .livePricesAndSync:
            LivePricesAndSyncSettingsView(store: store)
        case .historicalData:
            HistoricalDataSettingsView(store: store)
        case .tokens:
            TokenSettingsView()
        case .categories:
            CategorySettingsView()
        case .apiKeys:
            APIKeysSettingsView(secretStore: secretStore)
        case .debug:
            #if DEBUG
                DebugSettingsView()
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
