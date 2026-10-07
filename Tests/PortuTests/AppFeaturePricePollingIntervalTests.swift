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

    @Test func `onchain price fallback uses independent refresh interval`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var coinGeckoCoinFetchCount = 0
        nonisolated(unsafe) var coinGeckoTokenFetchCount = 0
        nonisolated(unsafe) var onchainFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request in
                if request.coinGeckoIDs == ["bitcoin"] {
                    coinGeckoCoinFetchCount += 1
                    #expect(request.onchainIdentities.isEmpty)
                    return PriceUpdate(prices: ["bitcoin": Decimal(coinGeckoCoinFetchCount)], changes24h: [:])
                }
                coinGeckoTokenFetchCount += 1
                #expect(request.coinGeckoIDs.isEmpty)
                #expect(request.onchainIdentities == [identity])
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchOnchainFallbackPrices = { identities in
                onchainFetchCount += 1
                #expect(identities == [identity])
                return PriceUpdate(
                    prices: [identity.historicalPriceID: Decimal(onchainFetchCount * 10)],
                    changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(20) }
            $0.pricePollingSettings.onchainFallbackInterval = { .seconds(5) }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin", identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin", identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = ["bitcoin": 1]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = ["bitcoin": 1, identity.historicalPriceID: 10]
            $0.lastPriceUpdate = testDate
        }

        await testClock.advance(by: .seconds(4))
        #expect(coinGeckoCoinFetchCount == 1)
        #expect(coinGeckoTokenFetchCount == 1)
        #expect(onchainFetchCount == 1)

        await testClock.advance(by: .seconds(1))
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = ["bitcoin": 1, identity.historicalPriceID: 20]
            $0.lastPriceUpdate = testDate
        }
        #expect(coinGeckoCoinFetchCount == 1)
        #expect(coinGeckoTokenFetchCount == 1)
        #expect(onchainFetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `display rate refresh keeps prices and leaves polling running`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var coinGeckoFetchCount = 0
        nonisolated(unsafe) var currentRate: Decimal = 2

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request in
                coinGeckoFetchCount += 1
                #expect(request.coinGeckoIDs == ["bitcoin"])
                return PriceUpdate(prices: ["bitcoin": 10], changes24h: ["bitcoin": 0.05])
            }
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in currentRate }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(2))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = 2
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: testDate)
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = ["bitcoin": 10]
            $0.priceChanges24h = ["bitcoin": 0.05]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }
        #expect(store.state.liveDisplayPrices == ["bitcoin": 20])

        // The periodic refresh moves the rate only: the USD book, the 24h change and the
        // update time stay, display prices follow the new rate, and polling is not restarted.
        currentRate = 3
        await testClock.advance(by: .seconds(900))
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(3))) {
            $0.currentUSDToDisplayRate = 3
        }
        #expect(store.state.livePricesUSD == ["bitcoin": 10])
        #expect(store.state.liveDisplayPrices == ["bitcoin": 30])
        #expect(store.state.priceChanges24h == ["bitcoin": 0.05])
        #expect(store.state.lastPriceUpdate == testDate)
        #expect(coinGeckoFetchCount == 1)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
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
            $0.priceService.fetchCoinGeckoPrices = { _ in
                PriceUpdate(prices: ["bitcoin": 10], changes24h: [:])
            }
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                fetchRateCallCount += 1
                return 1
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = ["bitcoin": 10]
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

    @Test func `onchain price fallback observes manual only changes after startup`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var onchainInterval: Duration?
        nonisolated(unsafe) var onchainFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request in
                #expect(request.coinGeckoIDs.isEmpty)
                #expect(request.onchainIdentities == [identity])
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchOnchainFallbackPrices = { identities in
                onchainFetchCount += 1
                #expect(identities == [identity])
                return PriceUpdate(
                    prices: [identity.historicalPriceID: Decimal(onchainFetchCount * 10)],
                    changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(100) }
            $0.pricePollingSettings.onchainFallbackInterval = { onchainInterval }
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
        #expect(onchainFetchCount == 0)

        onchainInterval = .seconds(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = [identity.historicalPriceID: 10]
            $0.lastPriceUpdate = testDate
        }
        #expect(onchainFetchCount == 1)

        onchainInterval = nil
        await testClock.advance(by: .seconds(30))
        #expect(onchainFetchCount == 1)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `manual only onchain price fallback suppresses automatic onchain calls`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var onchainFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request in
                #expect(request.coinGeckoIDs.isEmpty)
                #expect(request.onchainIdentities == [identity])
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.priceService.fetchOnchainFallbackPrices = { _ in
                onchainFetchCount += 1
                return PriceUpdate(prices: [identity.historicalPriceID: 10], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(100) }
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
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
        #expect(onchainFetchCount == 0)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }
}
