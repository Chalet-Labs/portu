import Foundation
import os
import PortuCore

public actor ZapperProvider: PortfolioDataProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL
    private static let logger = Logger(subsystem: "com.portu.network", category: "ZapperProvider")

    nonisolated public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: true,
            supportsHealthFactors: false)
    }

    public init(
        apiKey: String,
        session: URLSession = .shared,
        // Zapper API v2 (deprecated). Response may be a raw JSON array or a {"data": [...]} envelope.
        // See: https://github.com/Zapper-fi/protocol — v2 sunset announced but exact date TBD.
        baseURL: URL = URL(string: "https://api.zapper.xyz/v2")!) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        try await fetchForAllAddresses(context: context, fetch: fetchTokenBalances)
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        try await fetchForAllAddresses(context: context, fetch: fetchAppPositions)
    }

    private func fetchForAllAddresses(
        context: SyncContext,
        fetch: (String) async throws -> [PositionDTO]) async throws -> [PositionDTO] {
        var allPositions: [PositionDTO] = []
        for (address, _) in context.addresses {
            let positions = try await fetch(address)
            allPositions.append(contentsOf: positions)
        }
        return allPositions
    }

    private func fetchTokenBalances(address: String) async throws -> [PositionDTO] {
        try await parseTokenBalances(data: fetchEndpoint("balances/tokens", address: address))
    }

    private func fetchAppPositions(address: String) async throws -> [PositionDTO] {
        try await parseAppPositions(data: fetchEndpoint("apps/positions", address: address))
    }

    private func fetchEndpoint(_ path: String, address: String) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ZapperError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "addresses[]", value: address)]
        guard let url = components.url else {
            throw ZapperError.invalidResponse
        }
        return try await makeRequest(url: url)
    }

    private func makeRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZapperError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200 ... 299: return data
        case 429: throw ZapperError.rateLimited
        case 401, 403: throw ZapperError.unauthorized
        default: throw ZapperError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func parseTokenBalances(data: Data) throws -> [PositionDTO] {
        let items = try parseJSONArray(data)
        guard !items.isEmpty else { return [] }
        var positions: [PositionDTO] = []
        var droppedCount = 0
        var firstDroppedKeys: [String]?
        for item in items {
            guard
                let symbol = item["symbol"] as? String,
                let balanceUSD = item["balanceUSD"] as? Double,
                let balance = item["balance"] as? Double
            else {
                droppedCount += 1
                if firstDroppedKeys == nil {
                    firstDroppedKeys = Array(item.keys).sorted()
                }
                continue
            }
            let name = item["name"] as? String ?? symbol
            let chain = parseChain(item)
            let token = buildTokenDTO(
                item, role: .balance, symbol: symbol, name: name,
                amount: Decimal(abs(balance)), usdValue: Decimal(abs(balanceUSD)), chain: chain)
            positions.append(PositionDTO(
                positionType: .idle, chain: chain,
                protocolId: nil, protocolName: nil, protocolLogoURL: nil,
                healthFactor: nil, tokens: [token]))
        }
        if droppedCount > 0 {
            let keys = firstDroppedKeys.map { $0.joined(separator: ", ") } ?? "none"
            let total = items.count
            Self.logger.warning(
                "parseTokenBalances: dropped \(droppedCount, privacy: .public)/\(total, privacy: .public) items — keys: [\(keys, privacy: .public)]")
        }
        if positions.isEmpty {
            throw ZapperError.schemaChanged(context: "parseTokenBalances: 0/\(items.count) items parsed successfully")
        }
        return positions
    }

    private func parseAppPositions(data: Data) throws -> [PositionDTO] {
        let items = try parseJSONArray(data)
        guard !items.isEmpty else { return [] }
        var positions: [PositionDTO] = []
        var droppedCount = 0
        var firstDroppedKeys: [String]?
        for item in items {
            guard let appId = item["appId"] as? String else {
                droppedCount += 1
                if firstDroppedKeys == nil {
                    firstDroppedKeys = Array(item.keys).sorted()
                }
                continue
            }
            let posType: PositionType = switch item["type"] as? String {
            case "lending": .lending
            case "liquidity-pool": .liquidityPool
            case "staking": .staking
            case "farming": .farming
            default: .other
            }
            let chain = parseChain(item)
            guard let tokensJSON = item["tokens"] as? [[String: Any]] else {
                droppedCount += 1
                if firstDroppedKeys == nil {
                    firstDroppedKeys = Array(item.keys).sorted()
                }
                continue
            }
            let tokens = parsePositionTokens(tokensJSON, chain: chain)
            if !tokensJSON.isEmpty, tokens.isEmpty {
                droppedCount += 1
                if firstDroppedKeys == nil {
                    firstDroppedKeys = Array(item.keys).sorted()
                }
                continue
            }
            positions.append(PositionDTO(
                positionType: posType,
                chain: chain,
                protocolId: appId,
                protocolName: item["appName"] as? String,
                protocolLogoURL: item["appImage"] as? String,
                healthFactor: item["healthFactor"] as? Double,
                tokens: tokens))
        }
        if droppedCount > 0 {
            let keys = firstDroppedKeys.map { $0.joined(separator: ", ") } ?? "none"
            let total = items.count
            Self.logger.warning(
                "parseAppPositions: dropped \(droppedCount, privacy: .public)/\(total, privacy: .public) items — keys: [\(keys, privacy: .public)]")
        }
        if positions.isEmpty {
            throw ZapperError.schemaChanged(context: "parseAppPositions: 0/\(items.count) items parsed successfully")
        }
        return positions
    }

    private func parsePositionTokens(_ tokensJSON: [[String: Any]], chain: Chain? = nil) -> [TokenDTO] {
        var tokens: [TokenDTO] = []
        var droppedCount = 0
        var firstDroppedKeys: [String]?
        for item in tokensJSON {
            guard
                let symbol = item["symbol"] as? String,
                let balance = item["balance"] as? Double,
                let balanceUSD = item["balanceUSD"] as? Double
            else {
                droppedCount += 1
                if firstDroppedKeys == nil {
                    firstDroppedKeys = Array(item.keys).sorted()
                }
                continue
            }
            let role: TokenRole = switch item["type"] as? String {
            case "supply": .supply
            case "borrow": .borrow
            case "reward": .reward
            case "stake": .stake
            default: .balance
            }
            tokens.append(buildTokenDTO(
                item, role: role, symbol: symbol, name: item["name"] as? String ?? symbol,
                amount: Decimal(abs(balance)), usdValue: Decimal(abs(balanceUSD)),
                chain: parseChain(item) ?? chain))
        }
        if droppedCount > 0 {
            let keys = firstDroppedKeys.map { $0.joined(separator: ", ") } ?? "none"
            let total = tokensJSON.count
            Self.logger.warning(
                "parsePositionTokens: dropped \(droppedCount, privacy: .public)/\(total, privacy: .public) — keys: [\(keys, privacy: .public)]")
        }
        return tokens
    }

    private func parseChain(_ item: [String: Any]) -> Chain? {
        (item["network"] as? String).flatMap { Chain(rawValue: $0) }
    }

    // swiftlint:disable:next function_parameter_count
    private func buildTokenDTO(
        _ item: [String: Any], role: TokenRole, symbol: String, name: String,
        amount: Decimal, usdValue: Decimal, chain: Chain?) -> TokenDTO {
        TokenDTO(
            role: role, symbol: symbol, name: name,
            amount: amount, usdValue: usdValue,
            chain: chain, contractAddress: item["address"] as? String,
            debankId: nil, coinGeckoId: item["coingeckoId"] as? String,
            sourceKey: (item["address"] as? String).map { "zapper:\($0)" },
            logoURL: item["imgUrl"] as? String,
            category: .other, isVerified: item["verified"] as? Bool ?? false)
    }

    private func parseJSONArray(_ data: Data) throws -> [[String: Any]] {
        let json = try JSONSerialization.jsonObject(with: data)
        if let envelope = json as? [String: Any], let array = envelope["data"] as? [[String: Any]] {
            return array
        }
        if let array = json as? [[String: Any]] {
            return array
        }
        throw ZapperError.decodingFailed
    }
}

public enum ZapperError: Error, LocalizedError, Sendable {
    case invalidResponse
    case rateLimited
    case unauthorized
    case httpError(statusCode: Int)
    case decodingFailed
    case schemaChanged(context: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Zapper API"
        case .rateLimited: "Zapper API rate limit exceeded"
        case .unauthorized: "Invalid Zapper API key"
        case let .httpError(code): "Zapper API returned HTTP \(code)"
        case .decodingFailed: "Failed to parse Zapper API response"
        case let .schemaChanged(ctx): "Zapper API schema may have changed: \(ctx)"
        }
    }
}
