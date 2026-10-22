import Foundation
@testable import Portu
import PortuCore
import Testing

/// The settings client on a real defaults suite, written the way the Settings window's
/// `@AppStorage` writes it (#123).
struct DashboardSettingsClientTests {
    @Test func `the client reads today's keys with the views' defaults`() throws {
        let (defaults, suite) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = DashboardSettingsClient.live(defaults: defaults)

        #expect(client.current() == .defaults)

        defaults.set(5.0, forKey: TokenDashboardSettings.minimumDashboardValueKey)
        defaults.set(false, forKey: TokenDashboardSettings.hideDustKey)
        defaults.set(true, forKey: HistoricalPriceBackfillSettings.isEnabledKey)
        defaults.set(#"["Bitcoin"," dogecoin "]"#, forKey: OverviewWatchlistStore.key)

        #expect(client.current() == DashboardSettings(
            dashboard: TokenDashboardSettings(minimumDashboardValue: 5, hideUnpriced: true, hideDust: false),
            isHistoricalBackfillEnabled: true,
            watchlistIDs: OverviewWatchlistStore.decode(#"["Bitcoin"," dogecoin "]"#)))
    }

    @Test func `changes start with the current settings and follow each distinct write`() async throws {
        let (defaults, suite) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let stream = DashboardSettingsClient.live(defaults: defaults).changes()

        defaults.set(true, forKey: TokenDashboardSettings.hideDustKey) // equal to the default: no change
        defaults.set("unrelated", forKey: "someOtherKey")
        defaults.set(false, forKey: TokenDashboardSettings.hideUnpricedKey)
        defaults.set(true, forKey: HistoricalPriceBackfillSettings.isEnabledKey)
        defaults.set(#"["cardano"]"#, forKey: OverviewWatchlistStore.key)
        let values = await Self.first(4, of: stream)

        try #require(values.count == 4, "\(values)")
        #expect(values[0] == .defaults)
        #expect(values[1].dashboard.hideUnpriced == false)
        #expect(values[1].dashboard.hideDust == true)
        #expect(values[2].isHistoricalBackfillEnabled)
        #expect(values[3].watchlistIDs == ["cardano"])
    }

    /// The first `count` values, or fewer if they don't arrive within `timeout`.
    private static func first(
        _ count: Int,
        of stream: AsyncStream<DashboardSettings>,
        timeout: Duration = .seconds(5)) async -> [DashboardSettings] {
        let collect = Task {
            var values: [DashboardSettings] = []
            for await value in stream {
                values.append(value)
                if values.count == count {
                    break
                }
            }
            return values
        }
        let timer = Task {
            try await Task.sleep(for: timeout)
            collect.cancel()
        }
        let values = await collect.value
        timer.cancel()
        return values
    }

    private static func suite() throws -> (UserDefaults, String) {
        let name = "DashboardSettingsClientTests.\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: name)), name)
    }
}
