import Foundation
@testable import Portu
import Testing

struct SettingsTabTests {
    @Test func `default visible tabs match settings sidebar order`() {
        let tabs = SettingsTab.visibleTabs(debugEnabled: true)

        #expect(tabs.map(\.title) == ["General", "API Keys", "Debug"])
        #expect(tabs.map(\.sidebarGlyph) == ["G", "K", "D"])
    }

    @Test func `search filters settings tabs by title and subtitle`() {
        let tabs = SettingsTab.visibleTabs(debugEnabled: true)

        #expect(SettingsTab.filter(tabs, query: "key") == [.apiKeys])
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
