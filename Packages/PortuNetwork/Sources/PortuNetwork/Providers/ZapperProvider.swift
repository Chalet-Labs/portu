import Foundation
import PortuCore

public actor ZapperProvider: PortfolioDataProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    public nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: true,
            supportsHealthFactors: false
        )
    }

    public init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.zapper.xyz/v2")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        var allPositions: [PositionDTO] = []
        for (address, _) in context.addresses {
            let positions = try await fetchTokenBalances(address: address)
            allPositions.append(contentsOf: positions)
        }
        return allPositions
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        var allPositions: [PositionDTO] = []
        for (address, _) in context.addresses {
            let positions = try await fetchAppPositions(address: address)
            allPositions.append(contentsOf: positions)
        }
        return allPositions
    }

    private func fetchTokenBalances(address: String) async throws -> [PositionDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("balances/tokens"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "addresses[]", value: address)]
        let data = try await makeRequest(url: components.url!)
        return try parseTokenBalances(data: data)
    }

    private func fetchAppPositions(address: String) async throws -> [PositionDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("apps/positions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "addresses[]", value: address)]
        let data = try await makeRequest(url: components.url!)
        return try parseAppPositions(data: data)
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
        case 200...299: return data
        case 429: throw ZapperError.rateLimited
        case 401, 403: throw ZapperError.unauthorized
        default: throw ZapperError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func parseTokenBalances(data: Data) throws -> [PositionDTO] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ZapperError.decodingFailed
        }
        return json.compactMap { item -> PositionDTO? in
            guard let symbol = item["symbol"] as? String,
                  let name = item["name"] as? String,
                  let balanceUSD = item["balanceUSD"] as? Double,
                  let balance = item["balance"] as? Double else { return nil }
            let chainStr = item["network"] as? String
            let chain = chainStr.flatMap { Chain(rawValue: $0) }
            let token = TokenDTO(
                role: .balance, symbol: symbol, name: name,
                amount: Decimal(balance), usdValue: Decimal(balanceUSD),
                chain: chain, contractAddress: item["address"] as? String,
                debankId: nil, coinGeckoId: item["coingeckoId"] as? String,
                sourceKey: (item["address"] as? String).map { "zapper:\($0)" },
                logoURL: item["imgUrl"] as? String,
                category: .other, isVerified: item["verified"] as? Bool ?? false
            )
            return PositionDTO(
                positionType: .idle, chain: chain,
                protocolId: nil, protocolName: nil, protocolLogoURL: nil,
                healthFactor: nil, tokens: [token]
            )
        }
    }

    private func parseAppPositions(data: Data) throws -> [PositionDTO] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ZapperError.decodingFailed
        }
        return json.compactMap { item -> PositionDTO? in
            guard let appId = item["appId"] as? String else { return nil }
            let posType: PositionType = switch item["type"] as? String {
            case "lending": .lending
            case "liquidity-pool": .liquidityPool
            case "staking": .staking
            case "farming": .farming
            default: .other
            }
            let tokens = parsePositionTokens(item["tokens"] as? [[String: Any]] ?? [])
            return PositionDTO(
                positionType: posType,
                chain: (item["network"] as? String).flatMap { Chain(rawValue: $0) },
                protocolId: appId,
                protocolName: item["appName"] as? String,
                protocolLogoURL: item["appImage"] as? String,
                healthFactor: item["healthFactor"] as? Double,
                tokens: tokens
            )
        }
    }

    private func parsePositionTokens(_ tokensJSON: [[String: Any]]) -> [TokenDTO] {
        tokensJSON.compactMap { item -> TokenDTO? in
            guard let symbol = item["symbol"] as? String,
                  let balance = item["balance"] as? Double,
                  let balanceUSD = item["balanceUSD"] as? Double else { return nil }
            let role: TokenRole = switch item["type"] as? String {
            case "supply": .supply
            case "borrow": .borrow
            case "reward": .reward
            case "stake": .stake
            default: .balance
            }
            return TokenDTO(
                role: role, symbol: symbol, name: item["name"] as? String ?? symbol,
                amount: Decimal(abs(balance)), usdValue: Decimal(abs(balanceUSD)),
                chain: (item["network"] as? String).flatMap { Chain(rawValue: $0) },
                contractAddress: item["address"] as? String,
                debankId: nil, coinGeckoId: item["coingeckoId"] as? String,
                sourceKey: (item["address"] as? String).map { "zapper:\($0)" },
                logoURL: item["imgUrl"] as? String,
                category: .other, isVerified: item["verified"] as? Bool ?? false
            )
        }
    }
}

enum ZapperError: Error, LocalizedError {
    case invalidResponse
    case rateLimited
    case unauthorized
    case httpError(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Zapper API"
        case .rateLimited: "Zapper API rate limit exceeded"
        case .unauthorized: "Invalid Zapper API key"
        case .httpError(let code): "Zapper API returned HTTP \(code)"
        case .decodingFailed: "Failed to parse Zapper API response"
        }
    }
}
