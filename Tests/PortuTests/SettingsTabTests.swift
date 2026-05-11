import Foundation
@testable import Portu
import PortuCore
import SwiftUI
import Testing

struct SettingsTabTests {
    @Test func `default visible tabs match settings sidebar order`() {
        let tabs = SettingsTab.visibleTabs(debugEnabled: true)

        #expect(tabs.map(\.title) == ["General", "Tokens", "Categories", "API Keys", "Debug"])
        #expect(tabs.map { SettingsIconography.sidebarSystemImage(for: $0) } == ["gearshape", "eye", "tag", "key", "wrench.and.screwdriver"])
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
        #expect(SettingsTab.filter(tabs, query: "price") == [.general])
        #expect(SettingsTab.filter(tabs, query: " ") == tabs)
    }

    @Test func `settings typography is compact for main detail presentation`() {
        #expect(SettingsMetrics.pageTitleSize < 38)
        #expect(SettingsMetrics.sectionTitleSize < 22)
        #expect(SettingsMetrics.sidebarWidth < 250)
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

    @Test func `price polling settings use shared defaults key and allowed values`() {
        let defaults = cleanDefaults()

        #expect(PricePollingSettings.refreshIntervalKey == "refreshInterval")
        #expect(PricePollingSettings.refreshIntervalSeconds(defaults: defaults) == 30)

        defaults.set(60.0, forKey: PricePollingSettings.refreshIntervalKey)
        #expect(PricePollingSettings.refreshIntervalSeconds(defaults: defaults) == 60)

        defaults.set(7.0, forKey: PricePollingSettings.refreshIntervalKey)
        #expect(PricePollingSettings.refreshIntervalSeconds(defaults: defaults) == 30)
    }

    private func cleanDefaults() -> UserDefaults {
        let suite = "com.portu.test.SettingsTab.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }
}
