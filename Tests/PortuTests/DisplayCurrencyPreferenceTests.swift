import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

@MainActor
struct DisplayCurrencyPreferenceTests {
    @Test func `preference saves and loads display currency`() throws {
        let suiteName = "DisplayCurrencyPreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(DisplayCurrencyPreference.load(from: defaults) == .usd)

        DisplayCurrencyPreference.save(.chf, to: defaults)

        #expect(DisplayCurrencyPreference.load(from: defaults) == .chf)
    }

    @Test func `currency selection persists the chosen currency`() async {
        nonisolated(unsafe) var savedCurrencies: [FiatCurrency] = []
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.displayCurrencyPreference.save = { currency in
                savedCurrencies.append(currency)
            }
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.selectedCurrency = .eur
            $0.historicalFXAvailability = .loading
            $0.prices = [:]
            $0.priceChanges24h = [:]
            $0.lastPriceUpdate = nil
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(1)))
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
        }

        #expect(savedCurrencies == [.eur])
    }
}
