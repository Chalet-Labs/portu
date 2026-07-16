import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

@MainActor
struct AppFeaturePricePollingIntervalTests {
    @Test func `price polling with no ids leaves connection idle`() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.startPricePolling([]))
    }

    @Test func `zapper price fallback uses independent refresh interval`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var coinGeckoCoinFetchCount = 0
        nonisolated(unsafe) var coinGeckoTokenFetchCount = 0
        nonisolated(unsafe) var zapperFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, _, _ in
                if request.coinGeckoIDs == ["bitcoin"] {
                    coinGeckoCoinFetchCount += 1
                    #expect(request.zapperIdentities.isEmpty)
                    return PriceUpdate(prices: ["bitcoin": Decimal(coinGeckoCoinFetchCount)], changes24h: [:])
                }
                coinGeckoTokenFetchCount += 1
                #expect(request.coinGeckoIDs.isEmpty)
                #expect(request.zapperIdentities == [identity])
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchZapperPrices = { identities, _, _ in
                zapperFetchCount += 1
                #expect(identities == [identity])
                return PriceUpdate(
                    prices: [identity.historicalPriceID: Decimal(zapperFetchCount * 10)],
                    changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(20) }
            $0.pricePollingSettings.zapperFallbackInterval = { .seconds(5) }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin", identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin", identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 1]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 1, identity.historicalPriceID: 10]
            $0.lastPriceUpdate = testDate
        }

        await testClock.advance(by: .seconds(4))
        #expect(coinGeckoCoinFetchCount == 1)
        #expect(coinGeckoTokenFetchCount == 1)
        #expect(zapperFetchCount == 1)

        await testClock.advance(by: .seconds(1))
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 1, identity.historicalPriceID: 20]
            $0.lastPriceUpdate = testDate
        }
        #expect(coinGeckoCoinFetchCount == 1)
        #expect(coinGeckoTokenFetchCount == 1)
        #expect(zapperFetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `zapper price fallback converts using the stored display rate`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let storedRate: Decimal = 2
        nonisolated(unsafe) var receivedRates: [Decimal] = []

        let store = TestStore(initialState: AppFeature.State(currentUSDToDisplayRate: storedRate)) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _, _, _ in
                PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchZapperPrices = { identities, _, rate in
                receivedRates.append(rate)
                #expect(identities == [identity])
                return PriceUpdate(prices: [identity.historicalPriceID: 10], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(100) }
            $0.pricePollingSettings.zapperFallbackInterval = { .seconds(5) }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }
        await store.receive(\.pricesReceived) {
            $0.prices = [identity.historicalPriceID: 10]
            $0.lastPriceUpdate = testDate
        }

        #expect(receivedRates == [storedRate])

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `coingecko price polling converts using the stored display rate`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let storedRate: Decimal = 2
        nonisolated(unsafe) var receivedRates: [Decimal] = []

        let store = TestStore(initialState: AppFeature.State(currentUSDToDisplayRate: storedRate)) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, _, rate in
                receivedRates.append(rate)
                #expect(request.coinGeckoIDs == ["bitcoin"])
                return PriceUpdate(prices: ["bitcoin": 10], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(100) }
            $0.pricePollingSettings.zapperFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 10]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        #expect(receivedRates == [storedRate])

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `display rate refresh restarts polling with a fresh fx rate`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let rate: Decimal = 2
        nonisolated(unsafe) var coinGeckoFetchCount = 0
        nonisolated(unsafe) var fetchRateCallCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, currency, _ in
                coinGeckoFetchCount += 1
                #expect(request.coinGeckoIDs == ["bitcoin"])
                return PriceUpdate(currency: currency, prices: ["bitcoin": 10], changes24h: [:])
            }
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                fetchRateCallCount += 1
                return rate
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.zapperFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(rate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = rate
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: testDate)
        }
        #expect(fetchRateCallCount == 1)

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 10]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }
        #expect(coinGeckoFetchCount == 1)

        // Nothing refreshes the rate until the display-rate-refresh interval elapses.
        await testClock.advance(by: .seconds(900))
        // Stale prices fetched under the old rate are cleared immediately so no view
        // pairs them with the new rate before the restarted poll returns fresh ones.
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(rate))) {
            $0.prices = [:]
            $0.lastPriceUpdate = nil
            $0.connectionStatus = .fetching
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 10]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        #expect(fetchRateCallCount == 2)
        #expect(coinGeckoFetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
            $0.prices = [:]
            $0.lastPriceUpdate = nil
        }
    }

    @Test func `display rate refresh keeps running without active price polling`() async {
        let testClock = TestClock()
        let rate: Decimal = 2
        nonisolated(unsafe) var fetchRateCallCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                fetchRateCallCount += 1
                return rate
            }
            $0.continuousClock = testClock
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(rate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = rate
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        }
        #expect(fetchRateCallCount == 1)

        // No view ever starts price polling here, yet the rate still refreshes on
        // schedule because it is armed by the selected currency, not by polling.
        await testClock.advance(by: .seconds(900))
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(rate)))
        #expect(fetchRateCallCount == 2)

        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
            $0.historicalFXAvailability = .available
        }
    }

    @Test func `display rate refresh does not run while polling in usd`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var fetchRateCallCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _, currency, _ in
                PriceUpdate(currency: currency, prices: ["bitcoin": 10], changes24h: [:])
            }
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                fetchRateCallCount += 1
                return 1
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.zapperFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 10]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        await testClock.advance(by: .seconds(900))
        #expect(fetchRateCallCount == 0)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `zapper price fallback observes manual only changes after startup`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var zapperInterval: Duration?
        nonisolated(unsafe) var zapperFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, _, _ in
                #expect(request.coinGeckoIDs.isEmpty)
                #expect(request.zapperIdentities == [identity])
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchZapperPrices = { identities, _, _ in
                zapperFetchCount += 1
                #expect(identities == [identity])
                return PriceUpdate(
                    prices: [identity.historicalPriceID: Decimal(zapperFetchCount * 10)],
                    changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(100) }
            $0.pricePollingSettings.zapperFallbackInterval = { zapperInterval }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        await testClock.advance(by: .seconds(30))
        #expect(zapperFetchCount == 0)

        zapperInterval = .seconds(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(\.pricesReceived) {
            $0.prices = [identity.historicalPriceID: 10]
            $0.lastPriceUpdate = testDate
        }
        #expect(zapperFetchCount == 1)

        zapperInterval = nil
        await testClock.advance(by: .seconds(30))
        #expect(zapperFetchCount == 1)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `manual only zapper price fallback suppresses automatic zapper calls`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var zapperFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, _, _ in
                #expect(request.coinGeckoIDs.isEmpty)
                #expect(request.zapperIdentities == [identity])
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchZapperPrices = { _, _, _ in
                zapperFetchCount += 1
                return PriceUpdate(prices: [identity.historicalPriceID: 10], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(100) }
            $0.pricePollingSettings.zapperFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        await testClock.advance(by: .seconds(30))
        #expect(zapperFetchCount == 0)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }
}
