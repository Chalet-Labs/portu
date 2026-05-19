import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import Testing

@MainActor
struct AppFeatureTests {
    // MARK: - Section Navigation

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

        await store.send(.stopPricePolling)
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
        }
        await store.receive(\.priceFetchFailed) {
            $0.connectionStatus = .error("Rate limited")
            // prices should NOT be cleared
        }

        await store.send(.stopPricePolling) {
            $0.connectionStatus = .idle
        }
    }

    @Test func `price polling ids split coingecko ids from zapper identities`() {
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
        #expect(request.zapperIdentities == [baseToken, ethToken, polygonZkToken])
    }

    @Test func `price polling id split preserves first seen identity priority`() {
        let priority = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xPriority")
        let lowerPriority = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xAaaa")

        let request = PricePollingIDResolver.split([
            priority.historicalPriceID,
            lowerPriority.historicalPriceID,
            priority.historicalPriceID
        ])

        #expect(request.zapperIdentities == [priority, lowerPriority])
    }

    @Test func `price polling updates merge coingecko and zapper results`() {
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
    @Test func `zapper fallback failure preserves coingecko prices`() async throws {
        struct ZapperUnavailable: Error {}

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
            fetchZapperUpdate: { identities in
                #expect(identities == [identity])
                throw ZapperUnavailable()
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
            fetchZapperUpdate: { identities in
                #expect(identities.isEmpty)
                return PricePollingIDResolver.emptyUpdate
            })

        #expect(update.prices["ethereum"] == nil)
        #expect(update.prices[identity.historicalPriceID] == Decimal(string: "2220.5"))
        #expect(update.changes24h[identity.historicalPriceID] == Decimal(string: "0.012"))
    }
}
