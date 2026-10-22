import ComposableArchitecture
import Foundation
import PortuCore
import Synchronization

// swiftformat:disable redundantSendable

/// The settings the portfolio read model depends on, as stored by the Settings window and the
/// Overview watchlist under today's `UserDefaults` keys.
struct DashboardSettings: Equatable, Sendable {
    var dashboard: TokenDashboardSettings
    var isHistoricalBackfillEnabled: Bool
    var watchlistIDs: [String]

    static let defaults = DashboardSettings(
        dashboard: .defaults,
        isHistoricalBackfillEnabled: HistoricalPriceBackfillSettings.defaultIsEnabled,
        watchlistIDs: [])

    /// Reads every key with the defaults the views' `@AppStorage` declarations use.
    init(defaults: UserDefaults) {
        self.init(
            dashboard: .fromDefaults(defaults),
            isHistoricalBackfillEnabled: HistoricalPriceBackfillSettings.isEnabled(defaults: defaults),
            watchlistIDs: OverviewWatchlistStore.decode(defaults.string(forKey: OverviewWatchlistStore.key) ?? "[]"))
    }

    init(dashboard: TokenDashboardSettings, isHistoricalBackfillEnabled: Bool, watchlistIDs: [String]) {
        self.dashboard = dashboard
        self.isHistoricalBackfillEnabled = isHistoricalBackfillEnabled
        self.watchlistIDs = watchlistIDs
    }
}

/// Reads and observes the dashboard settings. UserDefaults stays the one source of truth: the keys
/// contain periods, which `@Shared(.appStorage)` reports as an issue and can't observe through
/// key-value observation, so this client watches `UserDefaults.didChangeNotification` itself (#123).
struct DashboardSettingsClient {
    var current: @Sendable () -> DashboardSettings
    /// The current settings, then each distinct change, until the stream is cancelled.
    var changes: @Sendable () -> AsyncStream<DashboardSettings>
}

extension DashboardSettingsClient: DependencyKey {
    static let liveValue = Self.live(defaults: .standard)

    static let testValue = Self(
        current: { .defaults },
        changes: { AsyncStream { $0.finish() } })
}

extension DependencyValues {
    var dashboardSettings: DashboardSettingsClient {
        get { self[DashboardSettingsClient.self] }
        set { self[DashboardSettingsClient.self] = newValue }
    }
}

extension DashboardSettingsClient {
    static func live(defaults: UserDefaults) -> Self {
        // `UserDefaults` is documented as thread-safe.
        nonisolated(unsafe) let defaults = defaults
        return Self(
            current: { DashboardSettings(defaults: defaults) },
            changes: {
                AsyncStream { continuation in
                    // Reads and yields under one lock, so two notifications on different threads
                    // can't deliver an older value last.
                    let last = Mutex<DashboardSettings?>(nil)
                    let publish: @Sendable () -> Void = {
                        last.withLock { previous in
                            let settings = DashboardSettings(defaults: defaults)
                            guard previous != settings else { return }
                            previous = settings
                            continuation.yield(settings)
                        }
                    }
                    // Observe first, then read the current value, so no write falls in between.
                    nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                        forName: UserDefaults.didChangeNotification,
                        object: defaults,
                        queue: nil) { _ in publish() }
                    publish()
                    continuation.onTermination = { _ in
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
            })
    }
}
