#if DEBUG
    import ComposableArchitecture
    import Foundation
    @testable import Portu
    import PortuCore
    import Testing

    @MainActor
    struct DebugServerTCATests {
        private func makeStore(
            selectedCurrency: FiatCurrency = .usd,
            currentUSDToDisplayRate: Decimal = 1,
            livePricesUSD: [String: Decimal] = [:],
            priceChanges24h: [String: Decimal] = [:],
            lastPriceUpdate: Date? = nil,
            syncStatus: SyncStatus = .idle,
            syncProgress: Double = 0,
            connectionStatus: ConnectionStatus = .idle,
            storeIsEphemeral: Bool = false,
            syncEngine: SyncEngineClient = SyncEngineClient(sync: { _ in SyncResult(failedAccounts: []) })) -> StoreOf<AppFeature> {
            var state = AppFeature.State()
            state.selectedCurrency = selectedCurrency
            state.currentUSDToDisplayRate = currentUSDToDisplayRate
            state.livePricesUSD = livePricesUSD
            state.priceChanges24h = priceChanges24h
            state.lastPriceUpdate = lastPriceUpdate
            state.syncStatus = syncStatus
            state.syncProgress = syncProgress
            state.connectionStatus = connectionStatus
            state.storeIsEphemeral = storeIsEphemeral
            return Store(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.syncEngine = syncEngine
                $0.priceService = PriceServiceClient(
                    fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                    fetchHistoricalPrices: { _, _ in [] },
                    invalidateCache: {})
            }
        }

        // MARK: - GET /state/prices

        @Test func `prices endpoint returns display currency prices and changes`() async throws {
            let rate = try #require(Decimal(string: "0.9"))
            let store = makeStore(
                selectedCurrency: .chf,
                currentUSDToDisplayRate: rate,
                livePricesUSD: ["bitcoin": 50000],
                priceChanges24h: ["bitcoin": Decimal(2.5)],
                lastPriceUpdate: Date(timeIntervalSince1970: 1_000_000))
            let server = DebugServer(port: 19020, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19020/state/prices")))
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 200)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let prices = try #require(json["prices"] as? [String: Double])
            #expect(prices["bitcoin"] == 45000)
            let changes = try #require(json["changes24h"] as? [String: Double])
            #expect(changes["bitcoin"] == 2.5)
            #expect(json["currency"] as? String == "CHF")
            #expect(json["lastUpdate"] is String)
        }

        @Test func `prices endpoint omits lastUpdate when nil`() async throws {
            let store = makeStore()
            let server = DebugServer(port: 19021, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19021/state/prices")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["lastUpdate"] == nil)
        }

        // MARK: - GET /state/sync

        @Test func `sync endpoint returns idle statuses`() async throws {
            let store = makeStore(syncStatus: .idle, connectionStatus: .idle, storeIsEphemeral: true)
            let server = DebugServer(port: 19022, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19022/state/sync")))
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 200)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["syncStatus"] as? String == "idle")
            #expect(json["connectionStatus"] as? String == "idle")
            #expect(json["storeIsEphemeral"] as? Bool == true)
        }

        @Test func `sync endpoint serializes syncing with progress`() async throws {
            let store = makeStore(syncStatus: .syncing, syncProgress: 0.75)
            let server = DebugServer(port: 19023, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19023/state/sync")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["syncStatus"] as? String == "syncing")
            #expect(json["progress"] as? Double == 0.75)
        }

        @Test func `sync endpoint reports the progress of a running sync`() async throws {
            let progressDelivered = Gate()
            let release = Gate()
            let store = makeStore(syncEngine: SyncEngineClient(sync: { progress in
                await progress(SyncProgress(completedSteps: 1, totalSteps: 2))
                await progressDelivered.open()
                await release.wait()
                return SyncResult(failedAccounts: [])
            }))
            let server = DebugServer(port: 19034, store: store)
            try await server.start()
            defer { server.stop() }

            let url = try #require(URL(string: "http://127.0.0.1:19034/state/sync"))

            let sync = store.send(.syncTapped)
            await progressDelivered.wait()
            let data: Data
            do {
                (data, _) = try await URLSession.shared.data(from: url)
            } catch {
                // Let the sync finish so it isn't left parked on the gate.
                await release.open()
                await sync.finish()
                throw error
            }
            await release.open()
            await sync.finish()

            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["syncStatus"] as? String == "syncing")
            #expect(json["progress"] as? Double == 0.5)
            #expect(store.syncStatus == .idle)
        }

        @Test func `sync endpoint serializes completedWithErrors`() async throws {
            let store = makeStore(syncStatus: .completedWithErrors(failedAccounts: ["acc1", "acc2"]))
            let server = DebugServer(port: 19024, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19024/state/sync")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["syncStatus"] as? String == "completedWithErrors")
            #expect(json["failedAccounts"] as? [String] == ["acc1", "acc2"])
        }

        @Test func `sync endpoint serializes fetching connection status`() async throws {
            let store = makeStore(connectionStatus: .fetching)
            let server = DebugServer(port: 19025, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19025/state/sync")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["connectionStatus"] as? String == "fetching")
        }

        // MARK: - POST /actions/sync

        @Test func `sync action returns triggered true`() async throws {
            let store = makeStore()
            let server = DebugServer(port: 19026, store: store)
            try await server.start()
            defer { server.stop() }

            var request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:19026/actions/sync")))
            request.httpMethod = "POST"
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 200)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["triggered"] as? Bool == true)
        }

        // MARK: - POST /actions/price-invalidate

        @Test func `price invalidate action calls invalidateCache and returns triggered`() async throws {
            nonisolated(unsafe) var invalidateCalled = false
            let priceService = PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { _, _ in [] },
                invalidateCache: { invalidateCalled = true })
            let store = makeStore()
            let server = DebugServer(port: 19027, store: store, priceService: priceService)
            try await server.start()
            defer { server.stop() }

            var request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:19027/actions/price-invalidate")))
            request.httpMethod = "POST"
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 200)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["triggered"] as? Bool == true)

            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !invalidateCalled, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(invalidateCalled)
        }

        @Test func `price invalidate returns 500 when priceService is nil`() async throws {
            let store = makeStore()
            let server = DebugServer(port: 19029, store: store)
            try await server.start()
            defer { server.stop() }

            var request = try URLRequest(
                url: #require(URL(string: "http://127.0.0.1:19029/actions/price-invalidate")))
            request.httpMethod = "POST"
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try #require(response as? HTTPURLResponse)

            #expect(httpResponse.statusCode == 500)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["error"] as? String == "Price service unavailable")
        }

        // MARK: - Error state serialization

        @Test func `sync endpoint serializes error status with message`() async throws {
            let store = makeStore(syncStatus: .error("Sync failed"))
            let server = DebugServer(port: 19030, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19030/state/sync")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["syncStatus"] as? String == "error")
            #expect(json["errorMessage"] as? String == "Sync failed")
        }

        @Test func `sync endpoint serializes error connection status`() async throws {
            let store = makeStore(connectionStatus: .error("Connection lost"))
            let server = DebugServer(port: 19031, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19031/state/sync")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["connectionStatus"] as? String == "error")
            #expect(json["connectionErrorMessage"] as? String == "Connection lost")
        }

        // MARK: - 405 on TCA routes

        @Test func `state sync returns 405 for wrong method`() async throws {
            let store = makeStore()
            let server = DebugServer(port: 19028, store: store)
            try await server.start()
            defer { server.stop() }

            var request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:19028/state/sync")))
            request.httpMethod = "POST"
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 405)
            #expect(httpResponse.value(forHTTPHeaderField: "Allow") == "GET")
        }

        @Test func `actions sync returns 405 for GET`() async throws {
            let store = makeStore()
            let server = DebugServer(port: 19032, store: store)
            try await server.start()
            defer { server.stop() }

            let (_, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19032/actions/sync")))
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 405)
            #expect(httpResponse.value(forHTTPHeaderField: "Allow") == "POST")
        }

        @Test func `actions price-invalidate returns 405 for GET`() async throws {
            let store = makeStore()
            let server = DebugServer(port: 19033, store: store, priceService: PriceServiceClient(
                fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                fetchHistoricalPrices: { _, _ in [] },
                invalidateCache: {}))
            try await server.start()
            defer { server.stop() }

            let (_, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19033/actions/price-invalidate")))
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 405)
            #expect(httpResponse.value(forHTTPHeaderField: "Allow") == "POST")
        }
    }

    /// Holds waiters until it is opened; once open, it stays open.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            for waiter in waiters {
                waiter.resume()
            }
            waiters = []
        }

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
#endif
