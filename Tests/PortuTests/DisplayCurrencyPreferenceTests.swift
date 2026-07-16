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
        let testClock = TestClock()
        nonisolated(unsafe) var savedCurrencies: [FiatCurrency] = []
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.displayCurrencyPreference.save = { currency in
                savedCurrencies.append(currency)
            }
            $0.continuousClock = testClock
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(1))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDay = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        }

        // The preference is persisted only once the switch commits (after the rate
        // arrives), so a non-USD currency we could not display is never saved.
        #expect(savedCurrencies == [.eur])

        // Cancel the display-rate-refresh timer armed by the EUR commit; otherwise
        // it lingers and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
        }
    }
}
