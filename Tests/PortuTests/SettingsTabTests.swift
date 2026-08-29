import Foundation
@testable import Portu
import PortuCore
import SwiftUI
import Testing

struct SettingsTabTests {
    @Test func `default visible tabs match settings sidebar order`() {
        let tabs = SettingsTab.visibleTabs(debugEnabled: true)

        #expect(tabs.map(\.title) == [
            "General",
            "Updates",
            "Live Prices & Sync",
            "Historical Data",
            "Tokens",
            "Categories",
            "API Keys",
            "Debug"
        ])
        #expect(tabs.map { SettingsIconography.sidebarSystemImage(for: $0) } == [
            "gearshape",
            "arrow.down.circle",
            "arrow.triangle.2.circlepath",
            "chart.line.uptrend.xyaxis",
            "eye",
            "tag",
            "key",
            "wrench.and.screwdriver"
        ])
    }

    @Test func `settings mockup iconography uses semantic system symbols`() {
        #expect(SettingsSectionIcon.dashboardVisibility.systemImage == "eye")
        #expect(SettingsSectionIcon.apiKeys.systemImage == "key")
        #expect(SettingsIconography.apiKeyFieldSystemImage == "key")
        #expect(SettingsIconography.visibilityToggleActionSystemImage(isCurrentlyVisible: false) == "eye")
        #expect(SettingsIconography.visibilityToggleActionSystemImage(isCurrentlyVisible: true) == "eye.slash")
    }

    @Test func `section icon presentation pairs symbol with palette`() {
        let presentation = SettingsSectionIcon.apiKeys.presentation

        #expect(presentation.systemImage == SettingsSectionIcon.apiKeys.systemImage)
        #expect(presentation.foreground == SettingsDesign.warningOrange)
        #expect(presentation.background == SettingsDesign.orangeGlyphBackground)
    }

    @Test func `search filters settings tabs by title and subtitle`() {
        let tabs = SettingsTab.visibleTabs(debugEnabled: true)

        #expect(SettingsTab.filter(tabs, query: "key") == [.apiKeys])
        #expect(SettingsTab.filter(tabs, query: "pricing") == [.tokens])
        #expect(SettingsTab.filter(tabs, query: "category") == [.categories])
        #expect(SettingsTab.filter(tabs, query: "server") == [.debug])
        #expect(SettingsTab.filter(tabs, query: "price") == [.livePricesAndSync, .historicalData])
        #expect(SettingsTab.filter(tabs, query: "update") == [.updates])
        #expect(SettingsTab.filter(tabs, query: "currency") == [.general])
        #expect(SettingsTab.filter(tabs, query: "backfill") == [.historicalData])
        #expect(SettingsTab.filter(tabs, query: " ") == tabs)
    }

    @Test func `settings typography is compact for main detail presentation`() {
        #expect(SettingsMetrics.pageTitleSize < 38)
        #expect(SettingsMetrics.sectionTitleSize < 22)
        #expect(SettingsMetrics.sidebarWidth < 250)
        #expect(SettingsMetrics.pageMaxWidth <= 980)
        #expect(SettingsDesign.primaryButtonHorizontalPadding >= 14)
    }

    @Test func `settings omits explicit back navigation`() {
        #expect(SettingsMetrics.showsBackNavigation == false)
    }

    @Test func `settings sidebar header sits above page title in hierarchy`() {
        #expect(SettingsMetrics.sidebarHeaderTitle == "Settings")
        #expect(SettingsMetrics.sidebarHeaderTitleSize > SettingsMetrics.pageTitleSize)
    }

    @Test func `switch thumb fits inside track for custom toggle layout`() {
        #expect(SettingsDesign.switchThumbDiameter < SettingsDesign.switchTrackHeight)
        #expect(SettingsDesign.switchAnimationDuration == 0.25)
        #expect(SettingsDesign.primaryButtonMinWidth == 64)
        #expect(TokenDashboardSettings.hideDustTitle == "Hide dust")
        #expect(TokenDashboardSettings.hideUnpricedTitle == "Hide unpriced")
    }

    @Test func `category settings labels use configurable portfolio categories`() {
        let names = PortfolioCategoryDefaults.categorySnapshots.map(\.name)

        #expect(Array(names.prefix(3)) == ["BTC", "ETH", "SOL"])
        #expect(names.contains("Stablecoins"))
        #expect(names.contains("Other Tokens"))
        #expect(names.contains("Major") == false)
    }

    @Test func `api key inputs default secure and reveal only by explicit action`() {
        #expect(APIKeysSettingsLayout.inputMode(isVisible: false) == .secureText)
        #expect(APIKeysSettingsLayout.inputMode(isVisible: true) == .visibleText)
    }

    @Test func `older API key save completion cannot clear a newer pending edit`() throws {
        var state = APIKeysPendingSaveState()
        let firstSave = state.schedule()
        let newerSave = state.schedule()

        state.complete(firstSave)

        #expect(state.hasPendingSave)
        let flushGeneration = state.generationForFlush()
        #expect(flushGeneration != nil)

        state.complete(newerSave)
        #expect(state.hasPendingSave)
        try state.complete(#require(flushGeneration))
        #expect(!state.hasPendingSave)
    }

    @Test func `failed API key save remains pending for retry and flush`() throws {
        var state = APIKeysPendingSaveState()
        let failedSave = state.schedule()

        state.complete(failedSave, succeeded: false)

        #expect(state.hasPendingSave)
        let pendingFlushGeneration = state.generationForFlush()
        let flushGeneration = try #require(pendingFlushGeneration)
        state.complete(flushGeneration, succeeded: false)
        #expect(state.hasPendingSave)
    }

    @Test @MainActor
    func `API key save task waits for the previous save`() async {
        let order = SendableArray<Int>()
        let first = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            order.append(1)
        }
        let second = APIKeysSaveTaskCoordinator.makeTask(after: first, delay: nil) {
            order.append(2)
        }

        await second.value

        #expect(order.values == [1, 2])
    }

    @Test func `API key settings offers retry after load or save failures`() {
        #expect(APIKeysSettingsRetryPolicy.shouldShow(
            errorMessage: "Keychain unavailable",
            canSave: false))
        #expect(!APIKeysSettingsRetryPolicy.shouldShow(
            errorMessage: nil,
            canSave: false))
        #expect(APIKeysSettingsRetryPolicy.shouldShow(
            errorMessage: "stale",
            canSave: true))
        #expect(APIKeysSettingsRetryPolicy.isEnabled(isLoading: false))
        #expect(!APIKeysSettingsRetryPolicy.isEnabled(isLoading: true))
    }

    @Test func `price polling settings use shared defaults key and allowed values`() {
        let defaults = cleanDefaults()

        #expect(PricePollingSettings.refreshIntervalKey == "refreshInterval")
        #expect(PricePollingSettings.allowedRefreshIntervalSeconds == [30, 60, 300, 900, 3600, 21600, 86400])
        #expect(PricePollingSettings.refreshIntervalSeconds(defaults: defaults) == 30)

        defaults.set(86400.0, forKey: PricePollingSettings.refreshIntervalKey)
        #expect(PricePollingSettings.refreshIntervalSeconds(defaults: defaults) == 86400)

        defaults.set(15.0, forKey: PricePollingSettings.refreshIntervalKey)
        #expect(PricePollingSettings.refreshIntervalSeconds(defaults: defaults) == 30)
    }

    @Test func `provider interval settings use provider keys defaults and allowed values`() {
        let defaults = cleanDefaults()

        #expect(ProviderIntervalSettings.manualOnlySeconds == 0)
        #expect(ProviderIntervalSettings.onchainLivePriceIntervalKey == "providerIntervals.onchainLivePrice")
        #expect(ProviderIntervalSettings.onchainPortfolioSyncIntervalKey == "providerIntervals.onchainPortfolioSync")
        #expect(ProviderIntervalSettings.exchangePortfolioSyncIntervalKey == "providerIntervals.exchangePortfolioSync")

        #expect(ProviderIntervalSettings.allowedOnchainLivePriceIntervalSeconds == [0, 600, 3600, 21600, 86400])
        #expect(ProviderIntervalSettings.allowedOnchainPortfolioSyncIntervalSeconds == [0, 3600, 21600, 86400])
        #expect(ProviderIntervalSettings.allowedExchangePortfolioSyncIntervalSeconds == [0, 600, 3600, 21600, 86400])

        #expect(ProviderIntervalSettings.onchainLivePriceIntervalSeconds(defaults: defaults) == 3600)
        #expect(ProviderIntervalSettings.onchainPortfolioSyncIntervalSeconds(defaults: defaults) == 21600)
        #expect(ProviderIntervalSettings.exchangePortfolioSyncIntervalSeconds(defaults: defaults) == 3600)
    }

    @Test func `legacy Zapper portfolio interval migrates once without overwriting new value`() throws {
        let suite = "ProviderIntervalMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(86400.0, forKey: "providerIntervals.zapperPortfolioSync")

        ProviderIntervalSettings.migrateLegacyPreferences(defaults: defaults)

        #expect(defaults.double(forKey: ProviderIntervalSettings.onchainPortfolioSyncIntervalKey) == 86400)
        defaults.set(3600.0, forKey: ProviderIntervalSettings.onchainPortfolioSyncIntervalKey)
        ProviderIntervalSettings.migrateLegacyPreferences(defaults: defaults)
        #expect(defaults.double(forKey: ProviderIntervalSettings.onchainPortfolioSyncIntervalKey) == 3600)
        #expect(defaults.double(forKey: "providerIntervals.zapperPortfolioSync") == 86400)
    }

    @Test func `legacy Zapper live price interval migrates once without overwriting new value`() throws {
        let suite = "ProviderLivePriceIntervalMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.0, forKey: "providerIntervals.zapperLivePrice")

        ProviderIntervalSettings.migrateLegacyPreferences(defaults: defaults)

        #expect(defaults.object(forKey: ProviderIntervalSettings.onchainLivePriceIntervalKey) as? Double == 0)
        defaults.set(600.0, forKey: ProviderIntervalSettings.onchainLivePriceIntervalKey)
        ProviderIntervalSettings.migrateLegacyPreferences(defaults: defaults)
        #expect(defaults.double(forKey: ProviderIntervalSettings.onchainLivePriceIntervalKey) == 600)
        #expect(defaults.double(forKey: "providerIntervals.zapperLivePrice") == 0)
    }

    @Test func `provider interval settings convert manual only to no duration`() {
        let defaults = cleanDefaults()

        defaults.set(0.0, forKey: ProviderIntervalSettings.onchainLivePriceIntervalKey)
        defaults.set(0.0, forKey: ProviderIntervalSettings.onchainPortfolioSyncIntervalKey)
        defaults.set(0.0, forKey: ProviderIntervalSettings.exchangePortfolioSyncIntervalKey)

        #expect(ProviderIntervalSettings.onchainLivePriceInterval(defaults: defaults) == nil)
        #expect(ProviderIntervalSettings.onchainPortfolioSyncInterval(defaults: defaults) == nil)
        #expect(ProviderIntervalSettings.exchangePortfolioSyncInterval(defaults: defaults) == nil)

        defaults.set(7.0, forKey: ProviderIntervalSettings.onchainLivePriceIntervalKey)
        defaults.set(7.0, forKey: ProviderIntervalSettings.onchainPortfolioSyncIntervalKey)
        defaults.set(7.0, forKey: ProviderIntervalSettings.exchangePortfolioSyncIntervalKey)

        #expect(ProviderIntervalSettings.onchainLivePriceIntervalSeconds(defaults: defaults) == 3600)
        #expect(ProviderIntervalSettings.onchainPortfolioSyncIntervalSeconds(defaults: defaults) == 21600)
        #expect(ProviderIntervalSettings.exchangePortfolioSyncIntervalSeconds(defaults: defaults) == 3600)
    }

    @Test func `historical price settings use shared keys and labels`() {
        let defaults = cleanDefaults()

        #expect(HistoricalPriceBackfillSettings.isEnabledKey == "historicalPriceBackfill.isEnabled")
        #expect(HistoricalPriceBackfillSettings.isEnabled(defaults: defaults) == false)

        defaults.set(true, forKey: HistoricalPriceBackfillSettings.isEnabledKey)
        #expect(HistoricalPriceBackfillSettings.isEnabled(defaults: defaults) == true)
        #expect(HistoricalPriceBackfillSettings.sectionTitle == "Historical Prices")
        #expect(HistoricalPriceBackfillSettings.chartHorizonDays == 365)
    }

    @Test func `historical backfill status surfaces partial failures`() {
        let result = HistoricalBackfillResult(
            requestedAssets: 4,
            fetchedAssets: 3,
            skippedAssets: 1,
            insertedPoints: 10,
            updatedPoints: 2,
            failedCoinGeckoIDs: ["ethereum"])

        let message = HistoricalBackfillStatusFormatter.message(for: .succeeded(result))

        #expect(message.contains("Fetched 3 assets"))
        #expect(message.contains("failed 1"))
        #expect(message.contains("ethereum"))
    }

    @Test func `historical backfill status summarizes long failed identifier lists`() {
        let longIdentifier = "zapper:arbitrum:0x13ad3f1150db0e1e05fd32bdeeb7c110ee023de6"
        let result = HistoricalBackfillResult(
            requestedAssets: 4,
            fetchedAssets: 0,
            skippedAssets: 0,
            insertedPoints: 0,
            updatedPoints: 0,
            failedCoinGeckoIDs: [
                longIdentifier,
                "zapper:base:0x1234567890abcdef1234567890abcdef12345678",
                "ethereum",
                "bitcoin"
            ])

        let message = HistoricalBackfillStatusFormatter.message(for: .succeeded(result))

        #expect(message.contains("No prices fetched"))
        #expect(message.contains("failed 4 assets"))
        #expect(message.contains("provider access"))
        #expect(!message.contains(longIdentifier))
        #expect(!message.contains("zapper:"))
        #expect(message.count <= 80)
    }

    @Test func `historical backfill status names price sources while running`() {
        let message = HistoricalBackfillStatusFormatter.message(for: .running)

        #expect(message.contains("CoinGecko"))
        #expect(message.contains("Zerion"))
    }

    @Test func `historical backfill status surfaces cache clearing`() {
        let message = HistoricalBackfillStatusFormatter.message(for: .clearing)

        #expect(message == "Clearing historical price cache...")
    }

    @Test func `historical backfill status explains when local snapshots have no eligible price source`() {
        let result = HistoricalBackfillResult(
            requestedAssets: 0,
            fetchedAssets: 0,
            skippedAssets: 1050,
            insertedPoints: 0,
            updatedPoints: 0,
            failedCoinGeckoIDs: [])

        let message = HistoricalBackfillStatusFormatter.message(for: .succeeded(result))

        #expect(message.contains("No eligible assets"))
        #expect(message.contains("CoinGecko"))
        #expect(message.contains("onchain addresses"))
        #expect(message.contains("1050"))
    }

    private func cleanDefaults() -> UserDefaults {
        let suite = "com.portu.test.SettingsTab.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }
}
