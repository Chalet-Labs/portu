import Foundation

public struct TokenDashboardSettings: Equatable, Sendable {
    public static let minimumDashboardValueKey = "tokenSettings.minimumDashboardValue"
    public static let hideUnpricedKey = "tokenSettings.hideUnpriced"
    public static let hideDustKey = "tokenSettings.hideDust"
    public static let hideUnpricedTitle = "Hide unpriced"
    public static let hideUnpricedSubtitle = "Exclude tokens without a resolved price from dashboard totals."
    public static let hideDustTitle = "Hide dust"
    public static let defaultMinimumDashboardValue: Decimal = 1
    public static let defaults = TokenDashboardSettings()

    public var minimumDashboardValue: Decimal
    public var hideUnpriced: Bool
    public var hideDust: Bool

    public init(
        minimumDashboardValue: Decimal = Self.defaultMinimumDashboardValue,
        hideUnpriced: Bool = true,
        hideDust: Bool = true) {
        self.minimumDashboardValue = minimumDashboardValue
        self.hideUnpriced = hideUnpriced
        self.hideDust = hideDust
    }

    public static func fromDefaults(_ defaults: UserDefaults = .standard) -> Self {
        let storedMinimum = defaults.object(forKey: minimumDashboardValueKey) as? NSNumber
        return TokenDashboardSettings(
            minimumDashboardValue: storedMinimum.map { Decimal($0.doubleValue) } ?? defaultMinimumDashboardValue,
            hideUnpriced: defaults.object(forKey: hideUnpricedKey) as? Bool ?? true,
            hideDust: defaults.object(forKey: hideDustKey) as? Bool ?? true)
    }
}
