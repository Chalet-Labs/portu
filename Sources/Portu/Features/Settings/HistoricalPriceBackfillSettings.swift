import Foundation

enum HistoricalPriceBackfillSettings {
    static let isEnabledKey = "historicalPriceBackfill.isEnabled"
    static let defaultIsEnabled = false
    static let chartHorizonDays = 365
    static let sectionTitle = "Historical Prices"
    static let useBackfillTitle = "Use historical price backfill"
    static let backfillButtonTitle = "Backfill prices"
    static let clearCacheButtonTitle = "Clear cache"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: isEnabledKey) as? Bool ?? defaultIsEnabled
    }
}
