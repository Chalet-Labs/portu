import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

@MainActor
struct AppFeatureTests {
    // MARK: - B1: Section Navigation

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

    // MARK: - B2: Sync Happy Path

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

    // MARK: - B3: Sync Partial Failure

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

    // MARK: - B4: Sync Full Failure

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

    // MARK: - B5: Guard Against Double-Tap

    @Test func `sync guards against double tap`() async {
        let store = TestStore(
            initialState: AppFeature.State(syncStatus: .syncing(progress: 0.5))
        ) {
            AppFeature()
        }

        // Should be no-op when already syncing
        await store.send(.syncTapped)
    }

    // MARK: - B6 + B7: Price Polling

    @Test func `price polling receives update`() async {
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let expectedUpdate = PriceUpdate(
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": 2.5]
        )

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in expectedUpdate }
            $0.continuousClock = testClock
            $0.date = .constant(testDate)
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
        }
        await store.receive(\.pricesReceived) {
            $0.prices = ["bitcoin": 65000]
            $0.priceChanges24h = ["bitcoin": 2.5]
            $0.lastPriceUpdate = testDate
            $0.connectionStatus = .idle
        }

        // Stop polling to clean up the long-running effect
        await store.send(.stopPricePolling)
    }

    // MARK: - B8: Price Polling Error

    @Test func `price fetch error preserves existing prices`() async {
        struct PriceFailed: Error, LocalizedError {
            var errorDescription: String? {
                "Rate limited"
            }
        }

        let testClock = TestClock()

        let store = TestStore(
            initialState: AppFeature.State(prices: ["bitcoin": 60000])
        ) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in throw PriceFailed() }
            $0.continuousClock = testClock
        }

        await store.send(.startPricePolling(["bitcoin"])) {
            $0.connectionStatus = .fetching
        }
        await store.receive(\.priceFetchFailed) {
            $0.connectionStatus = .error("Rate limited")
            // prices should NOT be cleared
        }

        await store.send(.stopPricePolling)
    }

    // MARK: - B7: Price Merge (not replace)

    @Test func `prices merge with existing`() async {
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(
            initialState: AppFeature.State(
                prices: ["bitcoin": 60000, "ethereum": 3000]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(testDate)
        }

        await store.send(.pricesReceived(PriceUpdate(
            prices: ["bitcoin": 65000],
            changes24h: ["bitcoin": 2.5]
        ))) {
            $0.prices = ["bitcoin": 65000, "ethereum": 3000] // merged, not replaced
            $0.priceChanges24h = ["bitcoin": 2.5]
            $0.lastPriceUpdate = testDate
        }
    }
}
