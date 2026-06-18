import Foundation

enum PricePollingSettings {
    static let refreshIntervalKey = "refreshInterval"
    static let defaultRefreshIntervalSeconds = 30.0
    static let allowedRefreshIntervalSeconds: Set<Double> = [30, 60, 300, 900, 3600, 21600, 86400]

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

enum ProviderIntervalSettings {
    static let manualOnlySeconds = 0.0

    static let zapperLivePriceIntervalKey = "providerIntervals.zapperLivePrice"
    static let zapperPortfolioSyncIntervalKey = "providerIntervals.zapperPortfolioSync"
    static let exchangePortfolioSyncIntervalKey = "providerIntervals.exchangePortfolioSync"

    static let defaultZapperLivePriceIntervalSeconds = 3600.0
    static let defaultZapperPortfolioSyncIntervalSeconds = 21600.0
    static let defaultExchangePortfolioSyncIntervalSeconds = 3600.0

    static let allowedZapperLivePriceIntervalSeconds: Set<Double> = [0, 600, 3600, 21600, 86400]
    static let allowedZapperPortfolioSyncIntervalSeconds: Set<Double> = [0, 3600, 21600, 86400]
    static let allowedExchangePortfolioSyncIntervalSeconds: Set<Double> = [0, 600, 3600, 21600, 86400]

    static func zapperLivePriceIntervalSeconds(defaults: UserDefaults = .standard) -> Double {
        intervalSeconds(
            key: zapperLivePriceIntervalKey,
            defaultValue: defaultZapperLivePriceIntervalSeconds,
            allowedValues: allowedZapperLivePriceIntervalSeconds,
            defaults: defaults)
    }

    static func zapperLivePriceInterval(defaults: UserDefaults = .standard) -> Duration? {
        duration(for: zapperLivePriceIntervalSeconds(defaults: defaults))
    }

    static func zapperPortfolioSyncIntervalSeconds(defaults: UserDefaults = .standard) -> Double {
        intervalSeconds(
            key: zapperPortfolioSyncIntervalKey,
            defaultValue: defaultZapperPortfolioSyncIntervalSeconds,
            allowedValues: allowedZapperPortfolioSyncIntervalSeconds,
            defaults: defaults)
    }

    static func zapperPortfolioSyncInterval(defaults: UserDefaults = .standard) -> Duration? {
        duration(for: zapperPortfolioSyncIntervalSeconds(defaults: defaults))
    }

    static func exchangePortfolioSyncIntervalSeconds(defaults: UserDefaults = .standard) -> Double {
        intervalSeconds(
            key: exchangePortfolioSyncIntervalKey,
            defaultValue: defaultExchangePortfolioSyncIntervalSeconds,
            allowedValues: allowedExchangePortfolioSyncIntervalSeconds,
            defaults: defaults)
    }

    static func exchangePortfolioSyncInterval(defaults: UserDefaults = .standard) -> Duration? {
        duration(for: exchangePortfolioSyncIntervalSeconds(defaults: defaults))
    }

    private static func intervalSeconds(
        key: String,
        defaultValue: Double,
        allowedValues: Set<Double>,
        defaults: UserDefaults) -> Double {
        guard
            let stored = defaults.object(forKey: key) as? Double,
            allowedValues.contains(stored)
        else {
            return defaultValue
        }

        return stored
    }

    private static func duration(for seconds: Double) -> Duration? {
        guard seconds != manualOnlySeconds else { return nil }
        return .seconds(seconds)
    }
}
