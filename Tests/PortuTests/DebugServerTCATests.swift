#if DEBUG
    import ComposableArchitecture
    import Foundation
    @testable import Portu
    import PortuCore
    import Testing

    @MainActor
    struct DebugServerTCATests {
        private func makeStore(
            prices: [String: Decimal] = [:],
            priceChanges24h: [String: Decimal] = [:],
            lastPriceUpdate: Date? = nil,
            syncStatus: SyncStatus = .idle,
            connectionStatus: ConnectionStatus = .idle,
            storeIsEphemeral: Bool = false) -> StoreOf<AppFeature> {
            var state = AppFeature.State()
            state.prices = prices
            state.priceChanges24h = priceChanges24h
            state.lastPriceUpdate = lastPriceUpdate
            state.syncStatus = syncStatus
            state.connectionStatus = connectionStatus
            state.storeIsEphemeral = storeIsEphemeral
            return Store(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.syncEngine = SyncEngineClient(sync: { SyncResult(failedAccounts: []) })
                $0.priceService = PriceServiceClient(
                    fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                    invalidateCache: {})
            }
        }

        // MARK: - GET /state/prices

        @Test func `prices endpoint returns coin prices and changes`() async throws {
            let store = makeStore(
                prices: ["bitcoin": 50000],
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
            #expect(prices["bitcoin"] == 50000)
            let changes = try #require(json["changes24h"] as? [String: Double])
            #expect(changes["bitcoin"] != nil)
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
            let store = makeStore(syncStatus: .syncing(progress: 0.75))
            let server = DebugServer(port: 19023, store: store)
            try await server.start()
            defer { server.stop() }

            let (data, _) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19023/state/sync")))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["syncStatus"] as? String == "syncing")
            #expect(json["progress"] as? Double == 0.75)
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

            try await Task.sleep(for: .milliseconds(50))
            #expect(invalidateCalled)
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
        }
    }
#endif
