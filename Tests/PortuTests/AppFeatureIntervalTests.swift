import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

@MainActor
struct AppFeatureIntervalTests {
    @Test func `scheduled provider sync uses provider intervals`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var syncedScopes: [PortfolioSyncScope] = []

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.zapperPortfolioSyncInterval = { .seconds(10) }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { .seconds(21) }
            $0.syncEngine.syncScope = { scope in
                syncedScopes.append(scope)
                return SyncResult(failedAccounts: [])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(9)
        await testClock.advance(by: .seconds(9))
        #expect(syncedScopes.isEmpty)

        now = now.addingTimeInterval(1)
        await testClock.advance(by: .seconds(1))
        await store.receive(.scheduledSyncDue(.zapper)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.zapper])

        now = now.addingTimeInterval(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(.scheduledSyncDue(.zapper)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.zapper, .zapper])

        now = now.addingTimeInterval(1)
        await testClock.advance(by: .seconds(1))
        await store.receive(.scheduledSyncDue(.exchange)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.zapper, .zapper, .exchange])

        await store.send(.stopScheduledSync)
    }

    @Test func `scheduled provider sync observes manual only changes after startup`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var zapperInterval: Duration?
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.zapperPortfolioSyncInterval = { zapperInterval }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
            $0.syncEngine.syncScope = { scope in
                #expect(scope == .zapper)
                syncCount += 1
                return SyncResult(failedAccounts: [])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(30)
        await testClock.advance(by: .seconds(30))
        #expect(syncCount == 0)

        zapperInterval = .seconds(10)
        now = now.addingTimeInterval(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(.scheduledSyncDue(.zapper)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncCount == 1)

        zapperInterval = nil
        now = now.addingTimeInterval(30)
        await testClock.advance(by: .seconds(30))
        #expect(syncCount == 1)

        await store.send(.stopScheduledSync)
    }

    @Test func `manual only scheduled sync starts no automatic provider loops`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.zapperPortfolioSyncInterval = { nil }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
            $0.syncEngine.syncScope = { _ in
                syncCount += 1
                return SyncResult(failedAccounts: [])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(30)
        await testClock.advance(by: .seconds(30))
        #expect(syncCount == 0)
        await store.send(.stopScheduledSync)
    }

    @Test func `scheduled sync due skips while another sync is running`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(
            initialState: AppFeature.State(syncStatus: .syncing(progress: 0.25))) {
                AppFeature()
            } withDependencies: {
                $0.providerSyncSettings.zapperPortfolioSyncInterval = { .seconds(5) }
                $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
                $0.syncEngine.syncScope = { _ in
                    syncCount += 1
                    return SyncResult(failedAccounts: [])
                }
                $0.continuousClock = testClock
                $0.currentDate.now = { now }
            }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(5)
        await testClock.advance(by: .seconds(5))
        await store.receive(.scheduledSyncDue(.zapper))
        #expect(syncCount == 0)

        await store.send(.stopScheduledSync)
    }

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
            $0.priceService.fetchCoinGeckoPrices = { request, _ in
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
            $0.priceService.fetchCoinGeckoPrices = { _, _ in
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

    @Test func `zapper price fallback observes manual only changes after startup`() async {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let testClock = TestClock()
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var zapperInterval: Duration?
        nonisolated(unsafe) var zapperFetchCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchCoinGeckoPrices = { request, _ in
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
            $0.priceService.fetchCoinGeckoPrices = { request, _ in
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
