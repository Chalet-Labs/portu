import Foundation

enum PricePollingSettings {
    static let refreshIntervalKey = "refreshInterval"
    static let defaultRefreshIntervalSeconds = 30.0
    static let allowedRefreshIntervalSeconds: Set<Double> = [15, 30, 60, 300]

    static func refreshIntervalSeconds(defaults: UserDefaults = .standard) -> Double {
        guard
            let stored = defaults.object(forKey: refreshIntervalKey) as? Double,
            allowedRefreshIntervalSeconds.contains(stored)
        else {
            return defaultRefreshIntervalSeconds
        }

        return stored
    }

    static func refreshInterval(defaults: UserDefaults = .standard) -> Duration {
        .seconds(refreshIntervalSeconds(defaults: defaults))
    }
}
