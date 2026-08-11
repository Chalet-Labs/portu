// swiftlint:disable file_length

import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import Testing

@MainActor
// swiftlint:disable:next type_body_length
struct AppFeatureTests {
    // MARK: - Section Navigation

    @Test func `manual update check reaches updater client`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = {
                didCheckForUpdates = true
            }
        }

        await store.send(.checkForUpdatesTapped)
        await store.finish()

        #expect(didCheckForUpdates)
    }

    @Test func `section selection updates state`() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.sectionSelected(.accounts)) {
            $0.selectedSection = .accounts
        }
        await store.send(.sectionSelected(.exposure)) {
            $0.selectedSection = .exposure
        }
    }

    @Test func `section selection exits settings route`() async {
        let store = TestStore(initialState: AppFeature.State(selectedSection: .performance)) {
            AppFeature()
        }

        await store.send(.settingsSelected) {
            $0.isSettingsPresented = true
        }
        await store.send(.sectionSelected(.accounts)) {
            $0.selectedSection = .accounts
            $0.isSettingsPresented = false
        }
        #expect(store.state.detailRoute == .section(.accounts))
    }

    @Test func `settings route is presented as detail content`() async {
        let store = TestStore(initialState: AppFeature.State(selectedSection: .accounts)) {
            AppFeature()
        }

        #expect(store.state.detailRoute == .section(.accounts))
        await store.send(.settingsSelected) {
            $0.isSettingsPresented = true
        }
        #expect(store.state.detailRoute == .settings)
        #expect(store.state.selectedSection == .accounts)
    }

    @Test func `settings route clears sidebar section selection while preserving selected section`() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        #expect(store.state.sidebarSelection == .overview)
        await store.send(.settingsSelected) {
            $0.isSettingsPresented = true
        }
        #expect(store.state.sidebarSelection == nil)
        #expect(store.state.selectedSection == .overview)
    }

    // MARK: - Sync Happy Path

    @Test func `sync happy path`() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { SyncResult(failedAccounts: []) }
        }

        await store.send(.syncTapped) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.syncCompleted) {
            $0.syncStatus = .idle
        }
    }

    // MARK: - Sync Partial Failure

    @Test func `sync partial failure`() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { SyncResult(failedAccounts: ["Binance"]) }
        }

        await store.send(.syncTapped) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.syncCompleted) {
            $0.syncStatus = .completedWithErrors(failedAccounts: ["Binance"])
        }
    }

    // MARK: - Sync Full Failure

    @Test func `sync full failure`() async {
        struct SyncFailed: Error, LocalizedError {
            var errorDescription: String? {
                "Network unavailable"
            }
        }

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { throw SyncFailed() }
        }

        await store.send(.syncTapped) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.syncCompleted) {
            $0.syncStatus = .error("Network unavailable")
        }
    }

    // MARK: - Guard Against Double-Tap

    @Test func `sync guards against double tap`() async {
        let store = TestStore(
            initialState: AppFeature.State(syncStatus: .syncing(progress: 0.5))) {
                AppFeature()
            }

        // Should be no-op when already syncing
        await store.send(.syncTapped)
    }

    // MARK: - Price Polling

    @Test func `price polling receives update`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let expectedUpdate = PriceUpdate(
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": 2.5])

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in expectedUpdate }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 65000]
            $0.priceChanges24h = ["bitcoin": 2.5]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        // Stop polling to clean up the long-running effect
        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `price polling uses selected currency`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var capturedCurrency: FiatCurrency?

        let store = TestStore(initialState: AppFeature.State(selectedCurrency: .chf)) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _, currency, _ in
                capturedCurrency = currency
                return PriceUpdate(currency: currency, prices: ["bitcoin": 58000], changes24h: [:])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 58000]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }
        #expect(capturedCurrency == .chf)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `price polling requests coin and token prices independently`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var capturedRequests: [PricePollingRequest] = []

        let store = TestStore(initialState: AppFeature.State(selectedCurrency: .eur)) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, currency, _ in
                capturedRequests.append(request)
                #expect(request.coinGeckoIDs.isEmpty || request.onchainIdentities.isEmpty)
                if request.coinGeckoIDs == ["bitcoin"] {
                    return PriceUpdate(currency: currency, prices: ["bitcoin": 58000], changes24h: [:])
                }
                if request.onchainIdentities == [identity] {
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return PriceUpdate(
                        currency: currency,
                        prices: [identity.historicalPriceID: 2],
                        changes24h: [:])
                }
                return PriceUpdate(
                    currency: currency,
                    prices: ["bitcoin": 58000, identity.historicalPriceID: 2],
                    changes24h: [:])
            }
            $0.continuousClock = testClock
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin", identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin", identity.historicalPriceID]
        }
        await store.receive(.pricesReceived(PriceUpdate(
            currency: .eur,
            prices: ["bitcoin": 58000],
            changes24h: [:]))) {
                $0.prices = ["bitcoin": 58000]
                $0.lastPriceUpdate = testDate
                $0.connectionStatus = .idle
            }
        await store.receive(.pricesReceived(PriceUpdate(
            currency: .eur,
            prices: [identity.historicalPriceID: 2],
            changes24h: [:]))) {
                $0.prices = ["bitcoin": 58000, identity.historicalPriceID: 2]
                $0.lastPriceUpdate = testDate
            }

        #expect(capturedRequests == [
            PricePollingRequest(coinGeckoIDs: ["bitcoin"], onchainIdentities: []),
            PricePollingRequest(coinGeckoIDs: [], onchainIdentities: [identity])
        ])

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `mixed poll with coin failure and empty token update clears fetching`() async {
        struct CoinFailed: LocalizedError { var errorDescription: String? {
            "coin failed"
        } }
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)

        let store = TestStore(initialState: AppFeature.State(selectedCurrency: .eur)) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, currency, _ in
                if request.coinGeckoIDs == ["bitcoin"] {
                    throw CoinFailed()
                }
                // Token fetch succeeds but returns nothing for the onchain identity.
                return PriceUpdate(currency: currency, prices: [:], changes24h: [:])
            }
            $0.continuousClock = testClock
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin", identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin", identity.historicalPriceID]
        }
        // Without the fallback emit, neither branch would send an action and the
        // status would stay .fetching. The swallowed coin failure now surfaces.
        await store.receive(\.priceFetchFailed) {
            $0.connectionStatus = .error("coin failed")
        }

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `launch FX failure keeps the display on usd instead of the restored currency`() async {
        struct RateFailed: LocalizedError { var errorDescription: String? {
            "offline"
        } }
        let store = TestStore(initialState: AppFeature.State(
            selectedCurrency: .usd,
            pendingCurrency: .eur)) {
                AppFeature()
            } withDependencies: {
                $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in throw RateFailed() }
            }

        await store.send(.appLaunched) {
            $0.historicalFXAvailability = .loading
        }
        // The restored EUR preference must not stick with a stale 1:1 rate: the launch
        // stays on USD and surfaces the failure instead of relabeling USD balances.
        await store.receive(\.currentCurrencyConversionRateReceived) {
            $0.pendingCurrency = nil
            $0.historicalFXAvailability = .failed("offline")
        }
        #expect(store.state.selectedCurrency == .usd)
        #expect(store.state.currentUSDToDisplayRate == 1)
    }

    @Test func `currency change clears stale prices and ignores old currency updates`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: AppFeature.State(
            selectedCurrency: .usd,
            prices: ["bitcoin": 65000],
            priceChanges24h: ["bitcoin": 0.02],
            lastPriceUpdate: testDate)) {
                AppFeature()
            } withDependencies: {
                $0.currentDate.now = { testDate.addingTimeInterval(60) }
                $0.continuousClock = testClock
            }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(1))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.prices = [:]
            $0.priceChanges24h = [:]
            $0.lastPriceUpdate = nil
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: testDate.addingTimeInterval(60))
        }
        await store.send(.pricesReceived(PriceUpdate(
            currency: .usd,
            prices: ["bitcoin": 66000],
            changes24h: ["bitcoin": 0.01])))
        await store.send(.pricesReceived(PriceUpdate(
            currency: .eur,
            prices: ["bitcoin": 61000],
            changes24h: ["bitcoin": 0.03]))) {
                $0.prices = ["bitcoin": 61000]
                $0.priceChanges24h = ["bitcoin": 0.03]
                $0.lastPriceUpdate = testDate.addingTimeInterval(60)
                $0.connectionStatus = .idle
            }

        // Cancel the display-rate-refresh timer armed by the EUR commit; otherwise
        // it lingers and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
            $0.prices = [:]
            $0.priceChanges24h = [:]
            $0.lastPriceUpdate = nil
        }
    }

    @Test func `currency change refreshes current and historical fx state`() async throws {
        let testClock = TestClock()
        let currentRate = try #require(Decimal(string: "0.92"))
        let historicalResult = HistoricalFXRefreshResult(
            currency: .eur,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        nonisolated(unsafe) var capturedCurrentRequest: FiatCurrency?
        nonisolated(unsafe) var capturedHistoricalRequest: (FiatCurrency, Int)?

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { currency in
                capturedCurrentRequest = currency
                return currentRate
            }
            $0.currencyConversion.refreshHistoricalRates = { currency, days in
                capturedHistoricalRequest = (currency, days)
                return historicalResult
            }
            $0.continuousClock = testClock
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(currentRate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = currentRate
        }
        let completion = CurrencyConversionRefreshResult(
            currency: .eur,
            currentUSDToDisplayRate: currentRate,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        await store.receive(.currencyConversionRefreshCompleted(.eur, .success(completion))) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        }

        #expect(capturedCurrentRequest == .eur)
        #expect(capturedHistoricalRequest?.0 == .eur)
        #expect(capturedHistoricalRequest?.1 == HistoricalPriceBackfillSettings.chartHorizonDays)

        // Cancel the display-rate-refresh timer armed by the EUR commit; otherwise
        // it lingers and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
    }

    @Test func `currency change publishes current fx before historical refresh finishes`() async throws {
        let testClock = TestClock()
        let currentRate = try #require(Decimal(string: "0.92"))
        let historicalResult = HistoricalFXRefreshResult(
            currency: .eur,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        nonisolated(unsafe) var capturedCurrentRequest: FiatCurrency?
        nonisolated(unsafe) var capturedHistoricalRequest: (FiatCurrency, Int)?

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { currency in
                capturedCurrentRequest = currency
                return currentRate
            }
            $0.currencyConversion.refreshHistoricalRates = { currency, days in
                capturedHistoricalRequest = (currency, days)
                try await testClock.sleep(for: .seconds(1))
                return historicalResult
            }
            $0.continuousClock = testClock
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(currentRate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = currentRate
        }
        #expect(store.state.historicalFXAvailability == .loading)

        await testClock.advance(by: .seconds(1))
        let completion = CurrencyConversionRefreshResult(
            currency: .eur,
            currentUSDToDisplayRate: currentRate,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        await store.receive(.currencyConversionRefreshCompleted(.eur, .success(completion))) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        }

        #expect(capturedCurrentRequest == .eur)
        #expect(capturedHistoricalRequest?.0 == .eur)
        #expect(capturedHistoricalRequest?.1 == HistoricalPriceBackfillSettings.chartHorizonDays)

        // Cancel the display-rate-refresh timer armed by the EUR commit; otherwise
        // it lingers and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
    }

    @Test func `currency change does not restore a stale rate after a periodic tick lands first`() async throws {
        let testClock = TestClock()
        let initialRate = try #require(Decimal(string: "0.92"))
        let refreshedRate = try #require(Decimal(string: "0.95"))
        let historicalResult = HistoricalFXRefreshResult(
            currency: .eur,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        nonisolated(unsafe) var currentRateCallCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                currentRateCallCount += 1
                return currentRateCallCount == 1 ? initialRate : refreshedRate
            }
            $0.currencyConversion.refreshHistoricalRates = { _, _ in
                try await testClock.sleep(for: .seconds(950))
                return historicalResult
            }
            $0.continuousClock = testClock
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(initialRate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = initialRate
        }

        // The periodic display-rate timer ticks while the historical refresh from the
        // initial switch is still in flight, and lands a newer rate first.
        await testClock.advance(by: .seconds(900))
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(refreshedRate))) {
            $0.currentUSDToDisplayRate = refreshedRate
        }

        // The historical refresh completes afterward, carrying the rate captured before
        // it started (`initialRate`) — it must not overwrite the newer periodic rate.
        await testClock.advance(by: .seconds(50))
        let completion = CurrencyConversionRefreshResult(
            currency: .eur,
            currentUSDToDisplayRate: initialRate,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        await store.receive(.currencyConversionRefreshCompleted(.eur, .success(completion))) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        }

        #expect(store.state.currentUSDToDisplayRate == refreshedRate)

        // Cancel the display-rate-refresh timer armed by the EUR commit; otherwise
        // it lingers and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
    }

    @Test func `periodic tick tops up historical fx rates after a day rolls over`() async {
        let testClock = TestClock()
        let day1 = Date(timeIntervalSince1970: 1_000_000)
        let day2 = day1.addingTimeInterval(86400)
        let rate: Decimal = 2
        nonisolated(unsafe) var now = day1
        nonisolated(unsafe) var historicalDaysRequested: [Int] = []

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in rate }
            $0.currencyConversion.refreshHistoricalRates = { currency, days in
                historicalDaysRequested.append(days)
                return HistoricalFXRefreshResult(currency: currency, insertedHistoricalRates: 1, updatedHistoricalRates: 0)
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
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
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: day1)
        }
        #expect(historicalDaysRequested == [HistoricalPriceBackfillSettings.chartHorizonDays])

        // Roll over to the next UTC day before the periodic tick fires.
        now = day2
        await testClock.advance(by: .seconds(900))
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(rate)))
        await store.receive(\.historicalFXTopUpCompleted) {
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: day2)
        }
        // The second request uses the small top-up window, not the full backfill.
        #expect(historicalDaysRequested == [HistoricalPriceBackfillSettings.chartHorizonDays, 2])

        // Cancel the display-rate-refresh timer armed by the EUR commit; otherwise
        // it lingers and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
    }

    @Test func `periodic tick retries the historical backfill after the initial fetch failed`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let rate: Decimal = 2
        nonisolated(unsafe) var historicalCallCount = 0
        nonisolated(unsafe) var historicalDaysRequested: [Int] = []

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in rate }
            $0.currencyConversion.refreshHistoricalRates = { currency, days in
                historicalCallCount += 1
                historicalDaysRequested.append(days)
                if historicalCallCount == 1 {
                    throw CurrencyConversionRefreshError(message: "offline")
                }
                return HistoricalFXRefreshResult(currency: currency, insertedHistoricalRates: 5, updatedHistoricalRates: 0)
            }
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
        await store.receive(.currencyConversionRefreshCompleted(
            .eur,
            .failure(CurrencyConversionRefreshError(message: "offline")))) {
                $0.historicalFXAvailability = .failed("offline")
            }

        // The periodic tick retries the historical backfill since none has ever succeeded.
        await testClock.advance(by: .seconds(900))
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(rate)))
        await store.receive(\.historicalFXTopUpCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: testDate)
        }
        // No successful backfill existed yet, so the retry still requests the full window.
        #expect(historicalDaysRequested == [
            HistoricalPriceBackfillSettings.chartHorizonDays,
            HistoricalPriceBackfillSettings.chartHorizonDays
        ])

        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
    }

    @Test func `switching currencies does not let one currencys stale day suppress anothers retry`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let eurRate: Decimal = 2
        let chfRate: Decimal = 3
        nonisolated(unsafe) var historicalCallCount = 0
        nonisolated(unsafe) var historicalRequests: [(FiatCurrency, Int)] = []

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { currency in
                currency == .eur ? eurRate : chfRate
            }
            $0.currencyConversion.refreshHistoricalRates = { currency, days in
                historicalCallCount += 1
                historicalRequests.append((currency, days))
                if currency == .chf, historicalCallCount == 2 {
                    // CHF's initial backfill fails; its periodic retry (below) succeeds.
                    throw CurrencyConversionRefreshError(message: "offline")
                }
                return HistoricalFXRefreshResult(currency: currency, insertedHistoricalRates: 1, updatedHistoricalRates: 0)
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        // EUR switch succeeds fully, stamping EUR's refresh day.
        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.eur, .success(eurRate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .eur
            $0.currentUSDToDisplayRate = eurRate
        }
        await store.receive(\.currencyConversionRefreshCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.eur] = HistoricalPriceCalendar.utcStartOfDay(for: testDate)
        }

        // Switch to CHF — its initial historical backfill fails.
        await store.send(.displayCurrencySelected(.chf)) {
            $0.pendingCurrency = .chf
            $0.historicalFXAvailability = .loading
        }
        await store.receive(.currentCurrencyConversionRateReceived(.chf, .success(chfRate))) {
            $0.pendingCurrency = nil
            $0.selectedCurrency = .chf
            $0.currentUSDToDisplayRate = chfRate
        }
        await store.receive(.currencyConversionRefreshCompleted(
            .chf,
            .failure(CurrencyConversionRefreshError(message: "offline")))) {
                $0.historicalFXAvailability = .failed("offline")
            }

        // The periodic tick for CHF must still retry — EUR's same-day stamp must not
        // suppress it (a single shared field would), and since CHF has no cached data
        // yet, the retry requests the full backfill window, not the small top-up.
        await testClock.advance(by: .seconds(900))
        await store.receive(.currentCurrencyConversionRateReceived(.chf, .success(chfRate)))
        await store.receive(\.historicalFXTopUpCompleted) {
            $0.historicalFXAvailability = .available
            $0.historicalFXLastRefreshDayByCurrency[.chf] = HistoricalPriceCalendar.utcStartOfDay(for: testDate)
        }

        #expect(historicalRequests.map(\.0) == [.eur, .chf, .chf])
        #expect(historicalRequests.last?.1 == HistoricalPriceBackfillSettings.chartHorizonDays)

        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
    }

    @Test func `currency switch stays on previous currency when current rate fails`() async {
        let store = TestStore(initialState: AppFeature.State(selectedCurrency: .usd)) {
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

        // The switch never committed: previous currency and its rate are preserved,
        // so no cached USD value is ever relabeled as EUR.
        #expect(store.state.selectedCurrency == .usd)
        #expect(store.state.currentUSDToDisplayRate == 1)
    }

    @Test func `immediate USD switch cancels an in-flight non-USD conversion`() async {
        let testClock = TestClock()
        let store = TestStore(initialState: AppFeature.State(selectedCurrency: .usd)) {
            AppFeature()
        } withDependencies: {
            $0.currencyConversion.fetchCurrentUSDToDisplayRate = { _ in
                try await testClock.sleep(for: .seconds(10))
                return 1
            }
        }

        await store.send(.displayCurrencySelected(.eur)) {
            $0.pendingCurrency = .eur
            $0.historicalFXAvailability = .loading
        }
        // Switching to USD commits immediately and must cancel the in-flight EUR
        // conversion; otherwise the effect lingers doing network work + writes whose
        // result the reducer discards, and the test store flags it as still running.
        await store.send(.displayCurrencySelected(.usd)) {
            $0.pendingCurrency = nil
            $0.historicalFXAvailability = .available
        }
    }

    @Test func `currency change ignores stale fx refreshes`() async throws {
        let store = TestStore(initialState: AppFeature.State(selectedCurrency: .chf)) {
            AppFeature()
        }

        let result = try CurrencyConversionRefreshResult(
            currency: .eur,
            currentUSDToDisplayRate: #require(Decimal(string: "0.92")),
            insertedHistoricalRates: 1,
            updatedHistoricalRates: 0)

        await store.send(.currencyConversionRefreshCompleted(.eur, .success(result)))
        #expect(store.state.currentUSDToDisplayRate == 1)
        #expect(store.state.historicalFXAvailability == .available)
    }

    @Test func `price polling respects configured refresh interval`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var fetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in
                fetchCount += 1
                return PriceUpdate(prices: ["bitcoin": Decimal(fetchCount)], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(5) }
            $0.continuousClock = testClock
            $0.currentDate.now = { testDate }
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 1]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        await testClock.advance(by: .seconds(4))
        #expect(fetchCount == 1)

        await testClock.advance(by: .seconds(1))
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 2]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    // MARK: - Price Polling Error

    @Test func `price fetch error preserves existing prices`() async {
        struct PriceFailed: Error, LocalizedError {
            var errorDescription: String? {
                "Rate limited"
            }
        }

        let testClock = TestClock()

        let store = TestStore(
            initialState: AppFeature.State(prices: ["bitcoin": 60000])) {
                AppFeature()
            } withDependencies: {
                $0.priceService.fetchPrices = { _ in throw PriceFailed() }
                $0.continuousClock = testClock
            }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["bitcoin"]
        }
        await store.receive(\.priceFetchFailed) {
            $0.connectionStatus = .error("Rate limited")
            // prices should NOT be cleared
        }

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `price polling ids split coingecko ids from onchain identities`() {
        let baseToken = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let ethToken = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xToken")
        let polygonZkToken = OnchainTokenIdentity(chain: .polygonZkEVM, contractAddress: "0xToken")

        let request = PricePollingIDResolver.split([
            " Bitcoin ",
            baseToken.historicalPriceID,
            "bitcoin",
            ethToken.historicalPriceID,
            "asset:polygonzkevm:0xToken",
            "",
            baseToken.historicalPriceID
        ])

        #expect(request.coinGeckoIDs == ["bitcoin"])
        #expect(request.onchainIdentities == [baseToken, ethToken, polygonZkToken])
    }

    @Test func `price polling id split preserves first seen identity priority`() {
        let priority = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xPriority")
        let lowerPriority = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xAaaa")

        let request = PricePollingIDResolver.split([
            priority.historicalPriceID,
            lowerPriority.historicalPriceID,
            priority.historicalPriceID
        ])

        #expect(request.onchainIdentities == [priority, lowerPriority])
    }

    @Test func `price polling id split preserves Solana mint case`() {
        let solana = OnchainTokenIdentity(chain: .solana, contractAddress: "SoLanaMiNtCase")

        let request = PricePollingIDResolver.split([
            solana.historicalPriceID,
            "BITCOIN"
        ])

        #expect(request.coinGeckoIDs == ["bitcoin"])
        #expect(request.onchainIdentities == [solana])
    }

    @Test func `price polling updates merge coingecko and onchain results`() {
        let update = PricePollingIDResolver.merge([
            PriceUpdate(prices: ["bitcoin": 70000], changes24h: ["bitcoin": 0.02]),
            PriceUpdate(prices: ["asset:base:0xtoken": 3], changes24h: ["asset:base:0xtoken": -0.01])
        ])

        #expect(update.prices == ["bitcoin": 70000, "asset:base:0xtoken": 3])
        #expect(update.changes24h == ["bitcoin": 0.02, "asset:base:0xtoken": -0.01])
    }

    // MARK: - PriceServiceClient invalidateCache

    @Test func `priceServiceClient invalidateCache is callable`() async {
        nonisolated(unsafe) var called = false
        let client = PriceServiceClient(
            fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
            fetchHistoricalPrices: { _, _ in [] },
            invalidateCache: { called = true })
        await client.invalidateCache()
        #expect(called)
    }

    // MARK: - Historical Price Backfill

    @Test func `historical backfill success updates settings status`() async {
        let result = HistoricalBackfillResult(
            requestedAssets: 2,
            fetchedAssets: 2,
            skippedAssets: 1,
            insertedPoints: 10,
            updatedPoints: 3,
            failedCoinGeckoIDs: [])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.historicalPriceBackfill.run = { result }
        }

        await store.send(.historicalPriceBackfill(.backfillButtonTapped)) {
            $0.historicalPriceBackfill.status = .running
        }
        await store.receive(\.historicalPriceBackfill.backfillCompleted) {
            $0.historicalPriceBackfill.status = .succeeded(result)
        }
    }

    @Test func `historical backfill clear resets status`() async {
        let initial = AppFeature.State(
            historicalPriceBackfill: HistoricalPriceBackfillFeature.State(
                status: .failed("Rate limited")))
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.historicalPriceBackfill.clearCache = {}
        }

        await store.send(.historicalPriceBackfill(.clearCacheButtonTapped)) {
            $0.historicalPriceBackfill.status = .clearing
        }
        await store.receive(\.historicalPriceBackfill.clearCacheCompleted) {
            $0.historicalPriceBackfill.status = .idle
        }
    }

    // MARK: - Price Merge (not replace)

    @Test func `prices merge with existing`() async {
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(
            initialState: AppFeature.State(
                prices: ["bitcoin": 60000, "ethereum": 3000])) {
            AppFeature()
        } withDependencies: {
            $0.currentDate.now = { testDate }
        }

        await store.send(.pricesReceived(PriceUpdate(
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": 2.5]))) {
                $0.prices = ["bitcoin": 65000, "ethereum": 3000] // merged, not replaced
                $0.priceChanges24h = ["bitcoin": 2.5]
                $0.lastPriceUpdate = testDate
            }
    }
}

nonisolated final class AppPriceMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (Data?, Int))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let (data, statusCode) = Self.requestHandler?(request) ?? (nil, 500)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct LivePriceUpdateBuilderTests {
    @Test func `onchain fallback failure preserves coingecko prices`() async throws {
        struct OnchainUnavailable: Error {}

        let identity = OnchainTokenIdentity(
            chain: .base,
            contractAddress: "0x4200000000000000000000000000000000000006")
        AppPriceMockURLProtocol.requestHandler = { request in
            guard let url = request.url else { return (nil, 500) }
            if url.path == "/api/v3/simple/price" {
                return (Data("""
                {"ethereum":{"usd":2220.5,"usd_24h_change":1.2}}
                """.utf8), 200)
            }
            if url.path == "/api/v3/simple/token_price/base" {
                return (Data("{}".utf8), 200)
            }
            return (nil, 500)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppPriceMockURLProtocol.self]
        let service = PriceService(session: URLSession(configuration: configuration), cacheTTL: 0)

        let update = try await LivePriceUpdateBuilder.fetchPrices(
            coinIds: ["ethereum", identity.historicalPriceID],
            priceService: service,
            fetchOnchainFallbackUpdate: { identities in
                #expect(identities == [identity])
                throw OnchainUnavailable()
            })

        #expect(update.prices["ethereum"] == Decimal(string: "2220.5"))
        #expect(update.changes24h["ethereum"] == Decimal(string: "0.012"))
        #expect(update.prices[identity.historicalPriceID] == nil)
    }

    @Test func `contract address fallback still runs when coingecko id request fails`() async throws {
        let identity = OnchainTokenIdentity(
            chain: .base,
            contractAddress: "0x4200000000000000000000000000000000000006")
        AppPriceMockURLProtocol.requestHandler = { request in
            guard let url = request.url else { return (nil, 500) }
            if url.path == "/api/v3/simple/price" {
                return (nil, 429)
            }
            if url.path == "/api/v3/simple/token_price/base" {
                return (Data("""
                {"0x4200000000000000000000000000000000000006":{"usd":2220.5,"usd_24h_change":1.2}}
                """.utf8), 200)
            }
            return (nil, 500)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppPriceMockURLProtocol.self]
        let service = PriceService(session: URLSession(configuration: configuration), cacheTTL: 0)

        let update = try await LivePriceUpdateBuilder.fetchPrices(
            coinIds: ["ethereum", identity.historicalPriceID],
            priceService: service,
            fetchOnchainFallbackUpdate: { identities in
                #expect(identities.isEmpty)
                return PricePollingIDResolver.emptyUpdate
            })

        #expect(update.prices["ethereum"] == nil)
        #expect(update.prices[identity.historicalPriceID] == Decimal(string: "2220.5"))
        #expect(update.changes24h[identity.historicalPriceID] == Decimal(string: "0.012"))
    }

    @Test func `non USD onchain fallback preserves normalized 24 hour changes`() async throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xabc")
        AppPriceMockURLProtocol.requestHandler = { request in
            guard let url = request.url else { return (nil, 500) }
            if url.path == "/api/v3/simple/token_price/base" {
                return (Data("{}".utf8), 200)
            }
            if url.path == "/api/v3/exchange_rates" {
                return (Data("""
                {"rates":{"usd":{"value":1},"eur":{"value":0.92}}}
                """.utf8), 200)
            }
            return (nil, 500)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppPriceMockURLProtocol.self]
        let service = PriceService(session: URLSession(configuration: configuration), cacheTTL: 0)

        let update = try await LivePriceUpdateBuilder.fetchPrices(
            coinIds: [identity.historicalPriceID],
            priceService: service,
            currency: .eur,
            fetchOnchainFallbackUpdate: { identities in
                #expect(identities == [identity])
                return PriceUpdate(
                    prices: [identity.historicalPriceID: 10],
                    changes24h: [identity.historicalPriceID: 0.05])
            })

        #expect(update.currency == .eur)
        #expect(update.prices[identity.historicalPriceID] == Decimal(string: "9.2"))
        #expect(update.changes24h[identity.historicalPriceID] == Decimal(string: "0.05"))
    }
}
