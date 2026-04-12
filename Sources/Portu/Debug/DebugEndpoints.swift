#if DEBUG

    import Foundation
    import PortuCore
    import SwiftData

    @MainActor
    enum DebugEndpoints {
        private static let iso8601: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        private static let iso8601NoFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        // MARK: - Route Registration

        static func register(on server: DebugServer, modelContainer: ModelContainer) {
            server.addRoute("GET", "/state/accounts") { _ in
                accounts(context: ModelContext(modelContainer))
            }

            server.addRoute("GET", "/state/positions") { request in
                positions(context: ModelContext(modelContainer), request: request)
            }

            server.addRoute("GET", "/state/assets") { request in
                assets(context: ModelContext(modelContainer), request: request)
            }

            server.addRoute("GET", "/state/snapshots/portfolio") { request in
                portfolioSnapshots(context: ModelContext(modelContainer), request: request)
            }

            server.addRoute("GET", "/state/snapshots/account") { request in
                accountSnapshots(context: ModelContext(modelContainer), request: request)
            }

            server.addRoute("GET", "/state/snapshots/asset") { request in
                assetSnapshots(context: ModelContext(modelContainer), request: request)
            }

            server.addRoute("GET", "/network/log") { request in
                await networkLog(request: request)
            }
        }

        // MARK: - /state/accounts

        static func accounts(context: ModelContext) -> HTTPResponse {
            guard let accounts = try? context.fetch(FetchDescriptor<Account>()) else {
                return errorResponse("Failed to fetch accounts")
            }
            let body: [[String: any Sendable]] = accounts.map { account in
                var dict: [String: any Sendable] = [
                    "id": account.id.uuidString,
                    "name": account.name,
                    "kind": account.kind.rawValue,
                    "dataSource": account.dataSource.rawValue,
                    "isActive": account.isActive,
                    "positionCount": account.positions.count
                ]
                if let date = account.lastSyncedAt {
                    dict["lastSyncedAt"] = iso8601.string(from: date)
                }
                if let error = account.lastSyncError {
                    dict["lastSyncError"] = error
                }
                return dict
            }
            return jsonArrayResponse(body)
        }

        // MARK: - /state/positions

        static func positions(context: ModelContext, request: HTTPRequest) -> HTTPResponse {
            let limit = request.intParam("limit", default: 100)

            if let rawId = request.queryParams["accountId"] {
                guard let accountId = UUID(uuidString: rawId) else {
                    return errorResponse("Invalid accountId", statusCode: 400)
                }
                guard let positions = try? context.fetch(FetchDescriptor<Position>()) else {
                    return errorResponse("Failed to fetch positions")
                }
                let filtered = positions.filter { $0.account?.id == accountId }
                return jsonArrayResponse(Array(filtered.prefix(limit)).map(positionDict))
            }

            var descriptor = FetchDescriptor<Position>()
            descriptor.fetchLimit = limit
            guard let positions = try? context.fetch(descriptor) else {
                return errorResponse("Failed to fetch positions")
            }
            return jsonArrayResponse(positions.map(positionDict))
        }

        private static func positionDict(_ position: Position) -> [String: any Sendable] {
            var dict: [String: any Sendable] = [
                "id": position.id.uuidString,
                "positionType": position.positionType.rawValue,
                "netUSDValue": position.netUSDValue.jsonDouble,
                "tokenCount": position.tokens.count
            ]
            if let chain = position.chain {
                dict["chain"] = chain.rawValue
            }
            if let name = position.protocolName {
                dict["protocolName"] = name
            }
            if let accountId = position.account?.id {
                dict["accountId"] = accountId.uuidString
            }
            return dict
        }

        // MARK: - /state/assets

        static func assets(context: ModelContext, request: HTTPRequest) -> HTTPResponse {
            let limit = request.intParam("limit", default: 50)
            let offset = request.intParam("offset", default: 0)

            var descriptor = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.symbol), SortDescriptor(\.id)])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit

            guard let assets = try? context.fetch(descriptor) else {
                return errorResponse("Failed to fetch assets")
            }

            let body: [[String: any Sendable]] = assets.map { asset in
                var dict: [String: any Sendable] = [
                    "id": asset.id.uuidString,
                    "symbol": asset.symbol,
                    "name": asset.name,
                    "category": asset.category.rawValue,
                    "isVerified": asset.isVerified
                ]
                if let geckoId = asset.coinGeckoId {
                    dict["coinGeckoId"] = geckoId
                }
                return dict
            }
            return jsonArrayResponse(body)
        }

        // MARK: - /state/snapshots/portfolio

        static func portfolioSnapshots(context: ModelContext, request: HTTPRequest) -> HTTPResponse {
            let limit = request.intParam("limit", default: 10)

            var descriptor = FetchDescriptor<PortfolioSnapshot>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchLimit = limit

            guard let snapshots = try? context.fetch(descriptor) else {
                return errorResponse("Failed to fetch portfolio snapshots")
            }

            let body: [[String: any Sendable]] = snapshots.map { snap in
                [
                    "id": snap.id.uuidString,
                    "timestamp": iso8601.string(from: snap.timestamp),
                    "totalValue": snap.totalValue.jsonDouble,
                    "idleValue": snap.idleValue.jsonDouble,
                    "deployedValue": snap.deployedValue.jsonDouble,
                    "debtValue": snap.debtValue.jsonDouble,
                    "isPartial": snap.isPartial
                ]
            }
            return jsonArrayResponse(body)
        }

        // MARK: - /state/snapshots/account

        static func accountSnapshots(context: ModelContext, request: HTTPRequest) -> HTTPResponse {
            guard let rawId = request.queryParams["accountId"] else {
                return errorResponse("Missing required parameter: accountId", statusCode: 400)
            }
            guard let accountId = UUID(uuidString: rawId) else {
                return errorResponse("Invalid accountId", statusCode: 400)
            }
            let limit = request.intParam("limit", default: 10)

            var descriptor = FetchDescriptor<AccountSnapshot>(
                predicate: #Predicate { $0.accountId == accountId },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchLimit = limit

            guard let snapshots = try? context.fetch(descriptor) else {
                return errorResponse("Failed to fetch account snapshots")
            }
            let body: [[String: any Sendable]] = snapshots.map { snap in
                [
                    "id": snap.id.uuidString,
                    "timestamp": iso8601.string(from: snap.timestamp),
                    "accountId": snap.accountId.uuidString,
                    "totalValue": snap.totalValue.jsonDouble,
                    "isFresh": snap.isFresh
                ]
            }
            return jsonArrayResponse(body)
        }

        // MARK: - /state/snapshots/asset

        static func assetSnapshots(context: ModelContext, request: HTTPRequest) -> HTTPResponse {
            guard let rawId = request.queryParams["assetId"] else {
                return errorResponse("Missing required parameter: assetId", statusCode: 400)
            }
            guard let assetId = UUID(uuidString: rawId) else {
                return errorResponse("Invalid assetId", statusCode: 400)
            }
            let limit = request.intParam("limit", default: 10)

            var descriptor = FetchDescriptor<AssetSnapshot>(
                predicate: #Predicate { $0.assetId == assetId },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchLimit = limit

            guard let snapshots = try? context.fetch(descriptor) else {
                return errorResponse("Failed to fetch asset snapshots")
            }
            let body: [[String: any Sendable]] = snapshots.map { snap in
                [
                    "id": snap.id.uuidString,
                    "timestamp": iso8601.string(from: snap.timestamp),
                    "assetId": snap.assetId.uuidString,
                    "symbol": snap.symbol,
                    "category": snap.category.rawValue,
                    "amount": snap.amount.jsonDouble,
                    "usdValue": snap.usdValue.jsonDouble,
                    "borrowAmount": snap.borrowAmount.jsonDouble,
                    "borrowUsdValue": snap.borrowUsdValue.jsonDouble
                ]
            }
            return jsonArrayResponse(body)
        }

        // MARK: - /network/log

        static func networkLog(
            buffer: NetworkLogBuffer = .shared,
            request: HTTPRequest) async -> HTTPResponse {
            let limit = request.intParam("limit", default: 50)
            let since: Date?
            if let rawSince = request.queryParams["since"] {
                let decoded = rawSince.removingPercentEncoding ?? rawSince
                guard let parsed = iso8601.date(from: decoded) ?? iso8601NoFractional.date(from: decoded) else {
                    return errorResponse("Invalid since parameter", statusCode: 400)
                }
                since = parsed
            } else {
                since = nil
            }

            let entries = await buffer.entries(since: since, limit: limit)
            let body: [[String: any Sendable]] = entries.map { entry in
                var dict: [String: any Sendable] = [
                    "id": entry.id.uuidString,
                    "timestamp": iso8601.string(from: entry.timestamp),
                    "url": entry.url,
                    "method": entry.method,
                    "responseSizeBytes": entry.responseSizeBytes,
                    "elapsed": entry.elapsed
                ]
                if let code = entry.statusCode {
                    dict["statusCode"] = code
                }
                if let error = entry.errorDescription {
                    dict["errorDescription"] = error
                }
                if !entry.headers.isEmpty {
                    dict["headers"] = entry.headers
                }
                return dict
            }
            return jsonArrayResponse(body)
        }

        // MARK: - JSON Helpers

        private static func jsonArrayResponse(_ body: [[String: any Sendable]], statusCode: Int = 200) -> HTTPResponse {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else {
                return errorResponse("serialization failed")
            }
            return HTTPResponse(statusCode: statusCode, body: data)
        }

        private static func errorResponse(_ message: String, statusCode: Int = 500) -> HTTPResponse {
            guard let data = try? JSONSerialization.data(withJSONObject: ["error": message]) else {
                return HTTPResponse(statusCode: 500, body: Data("{\"error\":\"serialization failed\"}".utf8))
            }
            return HTTPResponse(statusCode: statusCode, body: data)
        }
    }

    // MARK: - Query Param Helpers

    extension HTTPRequest {
        func intParam(_ key: String, default defaultValue: Int) -> Int {
            min(max(queryParams[key].flatMap(Int.init) ?? defaultValue, 0), 1000)
        }
    }

    // MARK: - Decimal JSON Serialization

    extension Decimal {
        var jsonDouble: Double {
            (self as NSDecimalNumber).doubleValue
        }
    }

#endif
