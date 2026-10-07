import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

/// Live prices are stored in USD and display prices are derived from them, so a rate
/// refresh or a currency switch never has to throw prices away or restart polling.
@MainActor
struct AppFeatureUSDPriceBookTests {
    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    private static func eurState(rate: Decimal = 2, pollingActive: Bool = true) -> AppFeature.State {
        var state = AppFeature.State()
        state.selectedCurrency = .eur
        state.currentUSDToDisplayRate = rate
        state.livePricesUSD = ["bitcoin": 100, "ethereum": 50]
        state.priceChanges24h = ["bitcoin": 0.05]
        state.lastPriceUpdate = testDate
        state.pricePollingIDs = pollingActive ? ["bitcoin", "ethereum"] : []
        // Today's historical FX is already fetched, so a refresh tick starts no top-up.
        state.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: testDate)
        return state
    }

    // MARK: - Derived display prices

    @Test func `display prices are the usd book scaled by the current rate`() throws {
        var state = AppFeature.State()
        state.livePricesUSD = ["bitcoin": 100, "ethereum": 3]

        #expect(state.liveDisplayPrices == ["bitcoin": 100, "ethereum": 3])

        state.currentUSDToDisplayRate = try #require(Decimal(string: "0.92"))
        let expectedEthereum = try #require(Decimal(string: "2.76"))

        #expect(state.liveDisplayPrices == ["bitcoin": 92, "ethereum": expectedEthereum])
        #expect(state.livePricesUSD == ["bitcoin": 100, "ethereum": 3])
    }

    // MARK: - Periodic rate refresh

    @Test(arguments: [true, false])
    func `rate refresh keeps prices and does not restart polling`(pollingActive: Bool) async {
        nonisolated(unsafe) var fetchCount = 0
        let store = TestStore(initialState: Self.eurState(pollingActive: pollingActive)) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in
                fetchCount += 1
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.continuousClock = TestClock()
            $0.currentDate.now = { Self.testDate }
        }

        await store.send(.currentCurrencyConversionRateReceived(.eur, .success(3))) {
            $0.currentUSDToDisplayRate = 3
        }

        #expect(store.state.livePricesUSD == ["bitcoin": 100, "ethereum": 50])
        #expect(store.state.liveDisplayPrices == ["bitcoin": 300, "ethereum": 150])
        #expect(store.state.priceChanges24h == ["bitcoin": 0.05])
        #expect(store.state.lastPriceUpdate == Self.testDate)
        #expect(fetchCount == 0)
    }

    // MARK: - Currency switch

    @Test func `switching currency keeps prices and does not restart polling`() async {
        nonisolated(unsafe) var fetchCount = 0
        var initial = AppFeature.State()
        initial.livePricesUSD = ["bitcoin": 100]
        initial.priceChanges24h = ["bitcoin": 0.05]
        initial.lastPriceUpdate = Self.testDate
        initial.pricePollingIDs = ["bitcoin"]
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in 2 }
            $0.priceService.fetchPrices = { _ in
                fetchCount += 1
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.continuousClock = TestClock()
            $0.currentDate.now = { Self.testDate }
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        // Nothing is shown under the new currency before its rate arrives: while the
        // switch is pending the old currency's prices stay on screen.
        #expect(store.state.selectedCurrency == .usd)
        #expect(store.state.liveDisplayPrices == ["bitcoin": 100])

        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(2))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = 2
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: Self.testDate)
        }
        #expect(store.state.liveDisplayPrices == ["bitcoin": 200])
        #expect(store.state.livePricesUSD == ["bitcoin": 100])
        #expect(store.state.lastPriceUpdate == Self.testDate)

        // Switching back cancels the rate-refresh timer armed by the EUR commit.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
        #expect(store.state.liveDisplayPrices == ["bitcoin": 100])
        #expect(store.state.priceChanges24h == ["bitcoin": 0.05])
        #expect(fetchCount == 0)
    }

    @Test func `failed rate fetch leaves the previous currency's prices untouched`() async {
        var initial = AppFeature.State()
        initial.livePricesUSD = ["bitcoin": 100]
        initial.lastPriceUpdate = Self.testDate
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                throw CurrencyConversionRefreshError(message: "offline")
            }
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(
            .eur, .failure(CurrencyConversionRefreshError(message: "offline")))) {
                $0.pendingCurrency = nil
                $0.historicalFXAvailability = .failed("offline")
            }

        #expect(store.state.liveDisplayPrices == ["bitcoin": 100])
        #expect(store.state.lastPriceUpdate == Self.testDate)
    }

    // MARK: - Incoming updates

    @Test func `only usd updates enter the usd book`() async {
        let store = TestStore(initialState: Self.eurState(pollingActive: false)) {
            AppFeature()
        } withDependencies: {
            $0.currentDate.now = { Self.testDate.addingTimeInterval(60) }
        }

        // A price that is not in USD would corrupt the book, so it is dropped.
        await store.send(.pricesReceived(PriceUpdate(
            currency: .eur,
            prices: ["bitcoin": 999],
            changes24h: ["bitcoin": 0.5])))

        await store.send(.pricesReceived(PriceUpdate(
            currency: .usd,
            prices: ["bitcoin": 110],
            changes24h: ["bitcoin": 0.06]))) {
                $0.livePricesUSD["bitcoin"] = 110
                $0.priceChanges24h["bitcoin"] = 0.06
                $0.lastPriceUpdate = Self.testDate.addingTimeInterval(60)
            }

        #expect(store.state.liveDisplayPrices == ["bitcoin": 220, "ethereum": 100])
    }
}
