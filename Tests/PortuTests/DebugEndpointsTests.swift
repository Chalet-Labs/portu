#if DEBUG
    import Foundation
    @testable import Portu
    import PortuCore
    import SwiftData
    import Testing

    @MainActor
    struct DebugEndpointsTests {
        private func makeTestContainer() throws -> ModelContainer {
            let schema = Schema([
                Account.self, WalletAddress.self, Position.self,
                PositionToken.self, Asset.self,
                PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        }

        // MARK: - /state/accounts

        @Test func `accounts returns all accounts with correct fields`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let syncDate = Date(timeIntervalSince1970: 1_700_000_000)
            let token = PositionToken(role: .balance, amount: 10, usdValue: 500)
            let position = Position(positionType: .idle, netUSDValue: 500, tokens: [token])
            let account = Account(
                name: "My Wallet", kind: .wallet, dataSource: .zapper,
                positions: [position], lastSyncedAt: syncDate, lastSyncError: "timeout")
            context.insert(account)
            try context.save()

            let response = DebugEndpoints.accounts(context: context)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            let item = json[0]
            #expect(item["name"] as? String == "My Wallet")
            #expect(item["kind"] as? String == "wallet")
            #expect(item["dataSource"] as? String == "zapper")
            #expect(item["isActive"] as? Bool == true)
            #expect(item["positionCount"] as? Int == 1)
            #expect(item["lastSyncedAt"] != nil)
            #expect(item["lastSyncError"] as? String == "timeout")
        }

        @Test func `accounts empty database returns empty array`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let response = DebugEndpoints.accounts(context: context)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.isEmpty)
        }

        // MARK: - /state/positions

        @Test func `positions returns all positions`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let position = Position(
                positionType: .lending, chain: .ethereum,
                protocolName: "Aave", netUSDValue: 1000)
            let account = Account(
                name: "Wallet", kind: .wallet, dataSource: .zapper,
                positions: [position])
            context.insert(account)
            try context.save()

            let request = HTTPRequest(method: "GET", path: "/state/positions", queryParams: [:])
            let response = DebugEndpoints.positions(context: context, request: request)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            #expect(json[0]["positionType"] as? String == "lending")
            #expect(json[0]["chain"] as? String == "ethereum")
            #expect(json[0]["protocolName"] as? String == "Aave")
            #expect(json[0]["netUSDValue"] as? Double == 1000.0)
            #expect(json[0]["tokenCount"] as? Int == 0)
        }

        @Test func `positions filters by accountId`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let pos1 = Position(positionType: .idle, netUSDValue: 100)
            let pos2 = Position(positionType: .staking, netUSDValue: 200)
            let account1 = Account(name: "A", kind: .wallet, dataSource: .zapper, positions: [pos1])
            let account2 = Account(name: "B", kind: .wallet, dataSource: .zapper, positions: [pos2])
            context.insert(account1)
            context.insert(account2)
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/positions",
                queryParams: ["accountId": account1.id.uuidString])
            let response = DebugEndpoints.positions(context: context, request: request)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            #expect(json[0]["positionType"] as? String == "idle")
        }

        @Test func `positions invalid accountId returns 400`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let request = HTTPRequest(
                method: "GET", path: "/state/positions",
                queryParams: ["accountId": "not-a-uuid"])
            let response = DebugEndpoints.positions(context: context, request: request)
            #expect(response.statusCode == 400)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            #expect(json["error"] as? String == "Invalid accountId")
        }

        // MARK: - /state/assets

        @Test func `assets returns paginated results`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            for i in 0 ..< 5 {
                context.insert(Asset(symbol: "T\(i)", name: "Token \(i)", category: .other))
            }
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/assets",
                queryParams: ["limit": "2", "offset": "1"])
            let response = DebugEndpoints.assets(context: context, request: request)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 2)
        }

        @Test func `assets includes correct fields`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let asset = Asset(
                symbol: "ETH", name: "Ethereum",
                coinGeckoId: "ethereum", category: .major, isVerified: true)
            context.insert(asset)
            try context.save()

            let request = HTTPRequest(method: "GET", path: "/state/assets", queryParams: [:])
            let response = DebugEndpoints.assets(context: context, request: request)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            let item = json[0]
            #expect(item["symbol"] as? String == "ETH")
            #expect(item["name"] as? String == "Ethereum")
            #expect(item["coinGeckoId"] as? String == "ethereum")
            #expect(item["category"] as? String == "major")
            #expect(item["isVerified"] as? Bool == true)
        }

        // MARK: - /state/snapshots/portfolio

        @Test func `portfolio snapshots sorted by timestamp desc`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let batchId = UUID()
            let old = PortfolioSnapshot(
                syncBatchId: batchId,
                timestamp: Date(timeIntervalSince1970: 1_000_000),
                totalValue: 100, idleValue: 50, deployedValue: 40,
                debtValue: 10, isPartial: false)
            let recent = PortfolioSnapshot(
                syncBatchId: batchId,
                timestamp: Date(timeIntervalSince1970: 2_000_000),
                totalValue: 200, idleValue: 100, deployedValue: 80,
                debtValue: 20, isPartial: true)
            context.insert(old)
            context.insert(recent)
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/portfolio",
                queryParams: ["limit": "10"])
            let response = DebugEndpoints.portfolioSnapshots(context: context, request: request)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 2)
            // Most recent first
            #expect(json[0]["totalValue"] as? Double == 200.0)
            #expect(json[1]["totalValue"] as? Double == 100.0)
            #expect(json[0]["isPartial"] as? Bool == true)
        }

        @Test func `portfolio snapshots respects limit`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let batchId = UUID()
            for i in 0 ..< 5 {
                context.insert(PortfolioSnapshot(
                    syncBatchId: batchId,
                    timestamp: Date(timeIntervalSince1970: Double(i) * 1000),
                    totalValue: Decimal(i * 100), idleValue: 0, deployedValue: 0,
                    debtValue: 0, isPartial: false))
            }
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/portfolio",
                queryParams: ["limit": "2"])
            let response = DebugEndpoints.portfolioSnapshots(context: context, request: request)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 2)
        }

        // MARK: - /state/snapshots/account

        @Test func `account snapshots filtered by accountId`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let targetId = UUID()
            let otherId = UUID()
            let batchId = UUID()
            context.insert(AccountSnapshot(
                syncBatchId: batchId, timestamp: .now,
                accountId: targetId, totalValue: 1000, isFresh: true))
            context.insert(AccountSnapshot(
                syncBatchId: batchId, timestamp: .now,
                accountId: otherId, totalValue: 2000, isFresh: false))
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/account",
                queryParams: ["accountId": targetId.uuidString])
            let response = DebugEndpoints.accountSnapshots(context: context, request: request)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            #expect(json[0]["totalValue"] as? Double == 1000.0)
            #expect(json[0]["isFresh"] as? Bool == true)
        }

        @Test func `account snapshots missing accountId returns 400`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/account", queryParams: [:])
            let response = DebugEndpoints.accountSnapshots(context: context, request: request)
            #expect(response.statusCode == 400)
        }

        @Test func `account snapshots invalid accountId returns 400`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/account",
                queryParams: ["accountId": "bad"])
            let response = DebugEndpoints.accountSnapshots(context: context, request: request)
            #expect(response.statusCode == 400)
        }

        // MARK: - /state/snapshots/asset

        @Test func `asset snapshots filtered by assetId`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let targetId = UUID()
            let batchId = UUID()
            context.insert(AssetSnapshot(
                syncBatchId: batchId, timestamp: .now,
                accountId: UUID(), assetId: targetId,
                symbol: "ETH", category: .major,
                amount: 10, usdValue: 25000))
            context.insert(AssetSnapshot(
                syncBatchId: batchId, timestamp: .now,
                accountId: UUID(), assetId: UUID(),
                symbol: "BTC", category: .major,
                amount: 1, usdValue: 67000))
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/asset",
                queryParams: ["assetId": targetId.uuidString])
            let response = DebugEndpoints.assetSnapshots(context: context, request: request)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            #expect(json[0]["symbol"] as? String == "ETH")
            #expect(json[0]["amount"] as? Double == 10.0)
            #expect(json[0]["usdValue"] as? Double == 25000.0)
        }

        @Test func `asset snapshots missing assetId returns 400`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/asset", queryParams: [:])
            let response = DebugEndpoints.assetSnapshots(context: context, request: request)
            #expect(response.statusCode == 400)
        }

        // MARK: - /network/log

        @Test func `network log returns entries`() async throws {
            let buffer = NetworkLogBuffer(capacity: 10)
            let entry = NetworkLogEntry(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                url: "https://api.example.com/data",
                method: "GET",
                statusCode: 200,
                responseSizeBytes: 1024,
                elapsed: 0.35,
                headers: [:])
            await buffer.append(entry)

            let request = HTTPRequest(method: "GET", path: "/network/log", queryParams: ["limit": "50"])
            let response = await DebugEndpoints.networkLog(buffer: buffer, request: request)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.count == 1)
            #expect(json[0]["url"] as? String == "https://api.example.com/data")
            #expect(json[0]["method"] as? String == "GET")
            #expect(json[0]["statusCode"] as? Int == 200)
            #expect(json[0]["responseSizeBytes"] as? Int == 1024)
            #expect(json[0]["elapsed"] as? Double == 0.35)
        }

        @Test func `network log empty buffer returns empty array`() async throws {
            let buffer = NetworkLogBuffer(capacity: 10)

            let request = HTTPRequest(method: "GET", path: "/network/log", queryParams: [:])
            let response = await DebugEndpoints.networkLog(buffer: buffer, request: request)
            #expect(response.statusCode == 200)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            #expect(json.isEmpty)
        }

        // MARK: - Decimal Serialization

        @Test func `decimal values serialize as numbers not strings`() throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)

            context.insert(PortfolioSnapshot(
                syncBatchId: UUID(), timestamp: .now,
                totalValue: 12345.67, idleValue: 100.50,
                deployedValue: 200.25, debtValue: 50, isPartial: false))
            try context.save()

            let request = HTTPRequest(
                method: "GET", path: "/state/snapshots/portfolio", queryParams: [:])
            let response = DebugEndpoints.portfolioSnapshots(context: context, request: request)

            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])
            let item = try #require(json.first)
            #expect(item["totalValue"] is Double)
            #expect(item["totalValue"] as? Double == 12345.67)
            #expect(item["idleValue"] as? Double == 100.50)
        }

        // MARK: - Integration: Route Registration

        @Test func `routes registered via DebugServer`() async throws {
            let container = try makeTestContainer()
            let context = ModelContext(container)
            context.insert(Account(name: "Integrated", kind: .manual, dataSource: .manual))
            try context.save()

            let server = DebugServer(port: 19040, modelContainer: container)
            try await server.start()
            defer { server.stop() }

            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:19040/state/accounts")))
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 200)
            #expect(httpResponse.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            #expect(json.count == 1)
            #expect(json[0]["name"] as? String == "Integrated")
        }
    }
#endif
