import ComposableArchitecture
import Foundation
import PortuCore

enum DisplayCurrencyPreference {
    static let storageKey = "DisplayCurrency"

    static func load(from defaults: UserDefaults = .standard) -> FiatCurrency {
        FiatCurrency(storageCode: defaults.string(forKey: storageKey))
    }

    static func save(_ currency: FiatCurrency, to defaults: UserDefaults = .standard) {
        defaults.set(currency.storageCode, forKey: storageKey)
    }
}

struct DisplayCurrencyPreferenceClient {
    var load: @Sendable () -> FiatCurrency
    var save: @Sendable (FiatCurrency) -> Void
}

extension DisplayCurrencyPreferenceClient: DependencyKey {
    static let liveValue = Self(
        load: { DisplayCurrencyPreference.load() },
        save: { DisplayCurrencyPreference.save($0) })
    static let testValue = Self(
        load: { .default },
        save: { _ in })
}

extension DependencyValues {
    var displayCurrencyPreference: DisplayCurrencyPreferenceClient {
        get { self[DisplayCurrencyPreferenceClient.self] }
        set { self[DisplayCurrencyPreferenceClient.self] = newValue }
    }
}
