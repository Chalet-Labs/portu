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

    static let onchainLivePriceIntervalKey = "providerIntervals.onchainLivePrice"
    static let onchainPortfolioSyncIntervalKey = "providerIntervals.onchainPortfolioSync"
    static let exchangePortfolioSyncIntervalKey = "providerIntervals.exchangePortfolioSync"

    static let defaultOnchainLivePriceIntervalSeconds = 3600.0
    static let defaultOnchainPortfolioSyncIntervalSeconds = 21600.0
    static let defaultExchangePortfolioSyncIntervalSeconds = 3600.0

    static let allowedOnchainLivePriceIntervalSeconds: Set<Double> = [0, 600, 3600, 21600, 86400]
    static let allowedOnchainPortfolioSyncIntervalSeconds: Set<Double> = [0, 3600, 21600, 86400]
    static let allowedExchangePortfolioSyncIntervalSeconds: Set<Double> = [0, 600, 3600, 21600, 86400]

    static func migrateLegacyPreferences(defaults: UserDefaults = .standard) {
        migrateLegacyValue(
            from: "providerIntervals.zapperLivePrice",
            to: onchainLivePriceIntervalKey,
            defaults: defaults)
        migrateLegacyValue(
            from: "providerIntervals.zapperPortfolioSync",
            to: onchainPortfolioSyncIntervalKey,
            defaults: defaults)
    }

    private static func migrateLegacyValue(
        from legacyKey: String,
        to currentKey: String,
        defaults: UserDefaults) {
        guard
            defaults.object(forKey: currentKey) == nil,
            let legacyValue = defaults.object(forKey: legacyKey) as? Double
        else {
            return
        }
        defaults.set(legacyValue, forKey: currentKey)
    }

    static func onchainLivePriceIntervalSeconds(defaults: UserDefaults = .standard) -> Double {
        intervalSeconds(
            key: onchainLivePriceIntervalKey,
            defaultValue: defaultOnchainLivePriceIntervalSeconds,
            allowedValues: allowedOnchainLivePriceIntervalSeconds,
            defaults: defaults)
    }

    static func onchainLivePriceInterval(defaults: UserDefaults = .standard) -> Duration? {
        duration(for: onchainLivePriceIntervalSeconds(defaults: defaults))
    }

    static func onchainPortfolioSyncIntervalSeconds(defaults: UserDefaults = .standard) -> Double {
        intervalSeconds(
            key: onchainPortfolioSyncIntervalKey,
            defaultValue: defaultOnchainPortfolioSyncIntervalSeconds,
            allowedValues: allowedOnchainPortfolioSyncIntervalSeconds,
            defaults: defaults)
    }

    static func onchainPortfolioSyncInterval(defaults: UserDefaults = .standard) -> Duration? {
        duration(for: onchainPortfolioSyncIntervalSeconds(defaults: defaults))
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
