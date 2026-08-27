import ComposableArchitecture
import PortuCore
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
        case .general: "Currency, price refresh, and software update preferences."
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
    static let pageMaxWidth: CGFloat = 920
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
    let secretStore: any SecretStore
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText = ""

    init(
        store: StoreOf<AppFeature>,
        secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        self.store = store
        self.secretStore = secretStore
    }

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
            APIKeysSettingsTab(secretStore: secretStore)
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
    @AppStorage(ProviderIntervalSettings.onchainLivePriceIntervalKey)
    private var onchainLivePriceInterval = ProviderIntervalSettings.defaultOnchainLivePriceIntervalSeconds
    @AppStorage(ProviderIntervalSettings.onchainPortfolioSyncIntervalKey)
    private var onchainPortfolioSyncInterval = ProviderIntervalSettings.defaultOnchainPortfolioSyncIntervalSeconds
    @AppStorage(ProviderIntervalSettings.exchangePortfolioSyncIntervalKey)
    private var exchangePortfolioSyncInterval = ProviderIntervalSettings.defaultExchangePortfolioSyncIntervalSeconds
    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    var body: some View {
        SettingsPage(tab: .general) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Live Prices",
                    subtitle: "Choose automatic refresh intervals by price provider.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsCurrencyPicker(store: store)

                            SettingsIntervalRow(
                                title: "CoinGecko live prices",
                                subtitle: "Default: 30 seconds. Longer intervals intentionally keep dashboard prices stale between refreshes.",
                                selection: $refreshInterval,
                                fallbackSeconds: PricePollingSettings.defaultRefreshIntervalSeconds,
                                options: .coinGeckoLivePrices)

                            SettingsIntervalRow(
                                title: "Zerion live price fallback",
                                subtitle: "Default: 1 hour. Used only for onchain tokens CoinGecko cannot price.",
                                selection: $onchainLivePriceInterval,
                                fallbackSeconds: ProviderIntervalSettings.defaultOnchainLivePriceIntervalSeconds,
                                options: .onchainLivePriceFallback)
                        }
                    }

                SettingsSectionCard(
                    title: "Portfolio Sync",
                    subtitle: "Control automatic portfolio sync calls by provider.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsIntervalRow(
                                title: "Zerion portfolio sync",
                                subtitle: "Default: 6 hours. Manual only disables scheduled Zerion portfolio refreshes.",
                                selection: $onchainPortfolioSyncInterval,
                                fallbackSeconds: ProviderIntervalSettings.defaultOnchainPortfolioSyncIntervalSeconds,
                                options: .onchainPortfolioSync)

                            SettingsIntervalRow(
                                title: "Exchange portfolio sync",
                                subtitle: "Default: 1 hour. Manual only disables scheduled exchange portfolio refreshes.",
                                selection: $exchangePortfolioSyncInterval,
                                fallbackSeconds: ProviderIntervalSettings.defaultExchangePortfolioSyncIntervalSeconds,
                                options: .exchangePortfolioSync)
                        }
                    }

                SettingsSectionCard(
                    title: HistoricalPriceBackfillSettings.sectionTitle,
                    subtitle: "Cache daily prices from CoinGecko and Zerion separately from Portu snapshots.",
                    icon: .priceUpdates) {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingsSwitchRow(
                                title: HistoricalPriceBackfillSettings.useBackfillTitle,
                                subtitle: "Use cached daily prices to extend charts before the first local snapshot.",
                                isOn: $historicalBackfillEnabled)

                            HStack(spacing: 10) {
                                Button {
                                    store.send(.historicalPriceBackfill(.backfillButtonTapped))
                                } label: {
                                    Label(HistoricalPriceBackfillSettings.backfillButtonTitle, systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.plain)
                                .settingsPrimaryButton(isDisabled: store.historicalPriceBackfill.status.isRunning)
                                .disabled(store.historicalPriceBackfill.status.isRunning)

                                Button {
                                    store.send(.historicalPriceBackfill(.clearCacheButtonTapped))
                                } label: {
                                    Label(HistoricalPriceBackfillSettings.clearCacheButtonTitle, systemImage: "trash")
                                }
                                .buttonStyle(.plain)
                                .settingsSecondaryButton(isDisabled: store.historicalPriceBackfill.status.isRunning)
                                .disabled(store.historicalPriceBackfill.status.isRunning)

                                Spacer(minLength: 0)
                            }

                            HistoricalBackfillStatusText(status: store.historicalPriceBackfill.status)
                        }
                    }

                SettingsSectionCard(
                    title: "Updates",
                    subtitle: "Privacy-preserving update checks that notify without downloading or restarting.",
                    icon: .softwareUpdates) {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsUpdateStatusNotice(
                                status: store.updaterStatus,
                                onDismiss: { store.send(.dismissUpdaterFailure) })

                            SettingsSwitchRow(
                                title: "Check for updates automatically",
                                subtitle: store.updaterStatus.isUpdaterEligible
                                    ? "Asks once, checks daily, and notifies without downloading or restarting."
                                    : "Update checks are not available in this build.",
                                isOn: Binding(
                                    get: { store.updatePreferences.automaticallyChecksForUpdates },
                                    set: { store.send(.setAutomaticChecksEnabled($0)) }))
                                .disabled(!store.updaterStatus.isUpdaterEligible)

                            SettingsUpdateChannelPicker(store: store)
                                .disabled(!store.updaterStatus.isUpdaterEligible)
                        }
                    }

                SettingsInfoCard(
                    title: "Auto-saved",
                    message: "These settings are stored locally with AppStorage and apply across Portu views.")
            }
        }
    }
}

private struct SettingsCurrencyPicker: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Display currency")
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .semibold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text("Portfolio values display in the selected fiat currency.")
                    .font(.caption)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Picker("Display currency", selection: currencyBinding) {
                ForEach(FiatCurrency.allCases, id: \.self) { currency in
                    Text(currency.displayCode).tag(currency)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.vertical, 4)
    }

    private var currencyBinding: Binding<FiatCurrency> {
        Binding(
            // A non-USD switch defers `selectedCurrency` until its FX rate arrives, so the
            // picker must show the effective target during that window, not the old currency.
            get: { store.pendingCurrency ?? store.selectedCurrency },
            set: { store.send(.displayCurrencySelected($0)) })
    }
}

private struct HistoricalBackfillStatusText: View {
    let status: HistoricalBackfillStatus

    var body: some View {
        HistoricalBackfillStatusRow(status: status)
    }
}

enum HistoricalBackfillStatusFormatter {
    static func message(for status: HistoricalBackfillStatus) -> String {
        switch status {
        case .idle:
            "No historical backfill run in this session."
        case .running:
            "Fetching historical prices from CoinGecko and Zerion..."
        case .clearing:
            "Clearing historical price cache..."
        case let .succeeded(result):
            successMessage(for: result)
        case let .failed(message):
            "Backfill failed: \(message)"
        }
    }

    private static func successMessage(for result: HistoricalBackfillResult) -> String {
        if result.requestedAssets == 0 {
            return "No eligible assets found for historical backfill. Skipped \(result.skippedAssets) "
                + "local snapshot assets because they do not have CoinGecko IDs, onchain addresses, or pricing overrides."
        }

        let baseMessage = "Fetched \(result.fetchedAssets) assets, inserted \(result.insertedPoints), "
            + "updated \(result.updatedPoints), skipped \(result.skippedAssets)."
        guard !result.failedCoinGeckoIDs.isEmpty else { return baseMessage }

        if result.fetchedAssets == 0, result.insertedPoints == 0, result.updatedPoints == 0 {
            return "No prices fetched; failed \(result.failedCoinGeckoIDs.count) assets. Check provider access."
        }

        if result.failedCoinGeckoIDs.count == 1, let id = result.failedCoinGeckoIDs.first {
            return baseMessage + " Partial success: failed 1 asset (\(displayIdentifier(id)))."
        }

        return baseMessage
            + " Partial success: failed \(result.failedCoinGeckoIDs.count) assets. Check provider access."
    }

    private static func displayIdentifier(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 24 else { return trimmed }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 3 {
            let head = parts.dropLast().joined(separator: ":")
            let tail = String(parts.last ?? "")
            return "\(head):\(tail.prefix(6))...\(tail.suffix(4))"
        }
        return "\(trimmed.prefix(12))...\(trimmed.suffix(8))"
    }
}
