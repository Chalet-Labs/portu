import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// Polling is identified by the set of price IDs it covers, not their order, and the
/// onchain fallback loop does not start over just because polling restarted.
@MainActor
struct AppFeaturePollingIdentityTests {
    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Set identity

    @Test func `same polling ids in another order start no new polling`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var fetchCount = 0
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in
                fetchCount += 1
                return PriceUpdate(prices: ["a": 1, "b": 2], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { Self.testDate }
        }

        await store.send(.startPricePolling(["a", "b"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["a", "b"]
        }
        await store.receive(\.pricesReceived) {
            $0.livePricesUSD = ["a": 1, "b": 2]
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }

        // Live-price ranking reorders the IDs; the poll is the same poll.
        await store.send(.startPricePolling(["b", "a"]))
        await testClock.advance(by: .seconds(1))
        #expect(fetchCount == 1)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `a different set of polling ids restarts polling`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var requests: [PricePollingRequest] = []
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request in
                requests.append(request)
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { Self.testDate }
        }

        await store.send(.startPricePolling(["a"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["a"]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }

        await store.send(.startPricePolling(["a", "b"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["a", "b"]
        }
        await store.receive(\.pricesReceived) {
            $0.connectionStatus = .idle
        }
        #expect(requests.map(\.coinGeckoIDs) == [["a"], ["a", "b"]])

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `polling starts again for the same ids after it was stopped`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var fetchCount = 0
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in
                fetchCount += 1
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(10000) }
            $0.pricePollingSettings.onchainFallbackInterval = { nil }
            $0.continuousClock = testClock
            $0.currentDate.now = { Self.testDate }
        }

        await store.send(.startPricePolling(["a", "b"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["a", "b"]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }
        await store.send(.stopPricePolling) {
            $0.pricePollingIDs = []
        }

        await store.send(.startPricePolling(["b", "a"])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = ["b", "a"]
        }
        await store.receive(\.pricesReceived) {
            $0.connectionStatus = .idle
        }
        #expect(fetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.pricePollingIDs = []
        }
    }

    // MARK: - Onchain fallback timing

    @Test func `a polling restart waits out the rest of the onchain interval`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        nonisolated(unsafe) var now = Self.testDate
        nonisolated(unsafe) var onchainFetchCount = 0
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.fetchOnchainFallbackPrices = { _ in
                onchainFetchCount += 1
                return PriceUpdate(prices: [identity.historicalPriceID: Decimal(onchainFetchCount)], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(1_000_000) }
            $0.pricePollingSettings.onchainFallbackInterval = { .seconds(3600) }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }
        await store.receive(\.onchainFallbackPricesReceived) {
            $0.livePricesUSD = [identity.historicalPriceID: 1]
            $0.onchainFallbackFetchedAt = [identity: Self.testDate]
        }
        #expect(onchainFetchCount == 1)

        // Five minutes in, polling restarts (the user left Overview and came back).
        now = Self.testDate.addingTimeInterval(300)
        await testClock.advance(by: .seconds(300))
        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate.addingTimeInterval(300)
            $0.connectionStatus = .idle
        }
        #expect(onchainFetchCount == 1)

        // The hour is counted from the first fetch: 55 minutes after the restart, not 60.
        await testClock.advance(by: .seconds(3299))
        #expect(onchainFetchCount == 1)

        now = Self.testDate.addingTimeInterval(3600)
        await testClock.advance(by: .seconds(1))
        await store.receive(\.onchainFallbackPricesReceived) {
            $0.livePricesUSD = [identity.historicalPriceID: 2]
            $0.lastPriceUpdate = Self.testDate.addingTimeInterval(3600)
            $0.onchainFallbackFetchedAt = [identity: Self.testDate.addingTimeInterval(3600)]
        }
        #expect(onchainFetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `a restart for other identities keeps the fetch times of the ones it left out`() async {
        let first = OnchainTokenIdentity(chain: .base, contractAddress: "0xFirst")
        let second = OnchainTokenIdentity(chain: .base, contractAddress: "0xSecond")
        let testClock = TestClock()
        nonisolated(unsafe) var now = Self.testDate
        let fetchedBatches = Mutex<[[OnchainTokenIdentity]]>([])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.fetchOnchainFallbackPrices = { identities in
                fetchedBatches.withLock { $0.append(identities) }
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(1_000_000) }
            $0.pricePollingSettings.onchainFallbackInterval = { .seconds(3600) }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }
        // Only when the loop fetches is under test, not the state around it.
        store.exhaustivity = .off

        await store.send(.startPricePolling([first.historicalPriceID]))
        await store.receive(\.onchainFallbackPricesReceived)
        #expect(fetchedBatches.withLock { $0 } == [[first]])

        // Five minutes later the screen polls another token: it was never fetched, so it goes now.
        now = Self.testDate.addingTimeInterval(300)
        await testClock.advance(by: .seconds(300))
        await store.send(.startPricePolling([second.historicalPriceID]))
        await store.receive(\.onchainFallbackPricesReceived)
        #expect(fetchedBatches.withLock { $0 } == [[first], [second]])

        // Back to the first token five minutes after that. It was fetched ten minutes ago, so
        // it waits for its hour, which the second token's fetch must not have reset.
        now = Self.testDate.addingTimeInterval(600)
        await testClock.advance(by: .seconds(300))
        await store.send(.startPricePolling([first.historicalPriceID]))
        await testClock.advance(by: .seconds(1))
        #expect(fetchedBatches.withLock { $0 } == [[first], [second]])

        now = Self.testDate.addingTimeInterval(3600)
        await testClock.advance(by: .seconds(2999))
        await store.receive(\.onchainFallbackPricesReceived)
        #expect(fetchedBatches.withLock { $0 } == [[first], [second], [first]])

        await store.send(.stopPricePolling)
    }

    @Test func `an identity that was never fetched is fetched right away on restart`() async {
        let known = OnchainTokenIdentity(chain: .base, contractAddress: "0xKnown")
        let joined = OnchainTokenIdentity(chain: .base, contractAddress: "0xJoined")
        let testClock = TestClock()
        nonisolated(unsafe) var now = Self.testDate
        nonisolated(unsafe) var fetchedBatches: [[OnchainTokenIdentity]] = []
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.fetchOnchainFallbackPrices = { identities in
                fetchedBatches.append(identities)
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(1_000_000) }
            $0.pricePollingSettings.onchainFallbackInterval = { .seconds(3600) }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startPricePolling([known.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [known.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }
        await store.receive(\.onchainFallbackPricesReceived) {
            $0.onchainFallbackFetchedAt = [known: Self.testDate]
        }

        // A token joins the polled set five minutes later. It must not wait for the hour.
        now = Self.testDate.addingTimeInterval(300)
        await testClock.advance(by: .seconds(300))
        await store.send(.startPricePolling([known.historicalPriceID, joined.historicalPriceID])) {
            $0.pricePollingIDs = [known.historicalPriceID, joined.historicalPriceID]
            $0.connectionStatus = .fetching
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate.addingTimeInterval(300)
            $0.connectionStatus = .idle
        }
        await store.receive(\.onchainFallbackPricesReceived) {
            $0.onchainFallbackFetchedAt = [
                known: Self.testDate.addingTimeInterval(300),
                joined: Self.testDate.addingTimeInterval(300)
            ]
        }
        #expect(fetchedBatches == [[known], [known, joined]])

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `an onchain fetch that was skipped is not recorded and is retried on restart`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        nonisolated(unsafe) var now = Self.testDate
        nonisolated(unsafe) var providerConfigured = false
        nonisolated(unsafe) var onchainFetchCount = 0
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.fetchOnchainFallbackPrices = { _ in
                onchainFetchCount += 1
                // With no provider key the live client fetches nothing and answers nil.
                return providerConfigured
                    ? PriceUpdate(prices: [identity.historicalPriceID: 5], changes24h: [:])
                    : nil
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(1_000_000) }
            $0.pricePollingSettings.onchainFallbackInterval = { .seconds(3600) }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }
        await testClock.advance(by: .seconds(1))
        #expect(onchainFetchCount == 1)
        // Nothing was fetched, so there is no fetch time to wait out.
        #expect(store.state.onchainFallbackFetchedAt.isEmpty)

        // The key is added and polling restarts five minutes later: the token goes right away.
        now = Self.testDate.addingTimeInterval(300)
        providerConfigured = true
        await testClock.advance(by: .seconds(299))
        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate.addingTimeInterval(300)
            $0.connectionStatus = .idle
        }
        await store.receive(\.onchainFallbackPricesReceived) {
            $0.livePricesUSD = [identity.historicalPriceID: 5]
            $0.onchainFallbackFetchedAt = [identity: Self.testDate.addingTimeInterval(300)]
        }
        #expect(onchainFetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }

    @Test func `a failed onchain fetch is retried when polling restarts`() async {
        struct OnchainDown: LocalizedError {
            var errorDescription: String? {
                "onchain provider down"
            }
        }

        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        nonisolated(unsafe) var onchainFetchCount = 0
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.fetchOnchainFallbackPrices = { _ in
                onchainFetchCount += 1
                throw OnchainDown()
            }
            $0.pricePollingSettings.refreshInterval = { .seconds(1_000_000) }
            $0.pricePollingSettings.onchainFallbackInterval = { .seconds(3600) }
            $0.continuousClock = testClock
            $0.currentDate.now = { Self.testDate }
        }

        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.lastPriceUpdate = Self.testDate
            $0.connectionStatus = .idle
        }
        await store.receive(\.priceFetchFailed) {
            $0.connectionStatus = .error("onchain provider down")
        }
        // Nothing was fetched, so there is no fetch time to wait out.
        #expect(store.state.onchainFallbackFetchedAt.isEmpty)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
        await store.send(.startPricePolling([identity.historicalPriceID])) {
            $0.connectionStatus = .fetching
            $0.pricePollingIDs = [identity.historicalPriceID]
        }
        await store.receive(\.pricesReceived) {
            $0.connectionStatus = .idle
        }
        await store.receive(\.priceFetchFailed) {
            $0.connectionStatus = .error("onchain provider down")
        }
        #expect(onchainFetchCount == 2)

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
            $0.pricePollingIDs = []
        }
    }
}
