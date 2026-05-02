import Foundation
import os
import PortuCore

public actor ZapperProvider: PortfolioDataProvider {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
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
        baseURL: URL = URL(string: "https://public.zapper.xyz/graphql")!) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        let requestContext = try makeRequestContext(from: context)
        var allPositions: [PositionDTO] = []
        var after: String?

        repeat {
            let variables = PortfolioVariables(
                addresses: requestContext.addresses,
                chainIds: requestContext.chainIds,
                first: 100,
                after: after)
            let response: GraphQLResponse<TokenBalancesData> = try await performGraphQL(
                query: Self.tokenBalancesQuery,
                variables: variables)
            let connection = try response.payload().portfolioV2.tokenBalances.byToken
            allPositions.append(contentsOf: connection.edges.map {
                position(from: $0.node)
            })
            after = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while after != nil

        return allPositions
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        let requestContext = try makeRequestContext(from: context)
        var allPositions: [PositionDTO] = []
        var after: String?

        repeat {
            let variables = PortfolioVariables(
                addresses: requestContext.addresses,
                chainIds: requestContext.chainIds,
                first: 100,
                after: after)
            let response: GraphQLResponse<AppBalancesData> = try await performGraphQL(
                query: Self.appBalancesQuery,
                variables: variables)
            let connection = try response.payload().portfolioV2.appBalances.byApp

            for edge in connection.edges {
                var positionEdges = edge.node.positionBalances.edges
                if edge.node.positionBalances.pageInfo.hasNextPage {
                    let extraEdges = try await fetchRemainingPositionEdges(
                        requestContext: requestContext,
                        appSlug: edge.node.app.slug,
                        after: edge.node.positionBalances.pageInfo.endCursor)
                    positionEdges.append(contentsOf: extraEdges)
                }
                allPositions.append(contentsOf: positionEdges.compactMap {
                    position(from: $0.node, appBalance: edge.node)
                })
            }

            after = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while after != nil

        return allPositions
    }

    private func fetchRemainingPositionEdges(
        requestContext: ZapperRequestContext,
        appSlug: String,
        after initialCursor: String?) async throws -> [AnyPositionBalanceEdge] {
        var allEdges: [AnyPositionBalanceEdge] = []
        var after = initialCursor

        while let cursor = after {
            let variables = AppPositionVariables(
                addresses: requestContext.addresses,
                chainIds: requestContext.chainIds,
                appSlug: appSlug,
                first: 100,
                after: cursor)
            let response: GraphQLResponse<AppBalancesData> = try await performGraphQL(
                query: Self.appPositionBalancesQuery,
                variables: variables)
            guard let appBalance = try response.payload().portfolioV2.appBalances.byApp.edges.first?.node else {
                return allEdges
            }
            let connection = appBalance.positionBalances
            allEdges.append(contentsOf: connection.edges)
            after = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        }

        return allEdges
    }

    private func makeRequestContext(from context: SyncContext) throws -> ZapperRequestContext {
        let addresses = context.addresses.map(\.address)
        let chains = context.addresses.compactMap(\.chain)
        let uniqueChains = Array(Set(chains))
        guard !uniqueChains.isEmpty else {
            return ZapperRequestContext(addresses: addresses, chainIds: nil)
        }

        var chainIds: [Int] = []
        for chain in uniqueChains {
            guard let chainId = Self.chainIds[chain] else {
                throw ZapperError.unsupportedChain(chain)
            }
            chainIds.append(chainId)
        }

        return ZapperRequestContext(addresses: addresses, chainIds: chainIds.sorted())
    }

    private func performGraphQL<Data: Decodable>(
        query: String,
        variables: some Encodable) async throws -> GraphQLResponse<Data> {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-zapper-api-key")
        request.httpBody = try encoder.encode(GraphQLRequest(query: query, variables: variables))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZapperError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200 ... 299:
            return try decoder.decode(GraphQLResponse<Data>.self, from: data)
        case 429:
            throw ZapperError.rateLimited
        case 401, 403:
            throw ZapperError.unauthorized
        default:
            throw ZapperError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func position(from node: TokenBalanceNode) -> PositionDTO {
        let chain = Self.chainsById[node.network.chainId]
        let token = TokenDTO(
            role: .balance,
            symbol: node.symbol,
            name: node.name,
            amount: Decimal(abs(node.balance)),
            usdValue: Decimal(abs(node.balanceUSD)),
            chain: chain,
            contractAddress: node.tokenAddress,
            debankId: nil,
            coinGeckoId: nil,
            sourceKey: "zapper:\(node.network.chainId):\(node.tokenAddress)",
            logoURL: node.imgUrlV2,
            category: .other,
            isVerified: node.verified)
        return PositionDTO(
            positionType: .idle,
            chain: chain,
            protocolId: nil,
            protocolName: nil,
            protocolLogoURL: nil,
            healthFactor: nil,
            tokens: [token])
    }

    private func position(from node: AnyPositionBalance, appBalance: AppBalanceNode) -> PositionDTO? {
        switch node {
        case let .contract(position):
            let tokens = position.tokens.map {
                tokenDTO(
                    from: $0.token,
                    role: role(for: $0.metaType),
                    sourceKey: tokenSourceKey(position.key, token: $0.token, chainId: appBalance.network.chainId),
                    chain: Self.chainsById[appBalance.network.chainId])
            }
            guard !tokens.isEmpty else { return nil }
            return PositionDTO(
                positionType: positionType(from: position.groupLabel),
                chain: Self.chainsById[appBalance.network.chainId],
                protocolId: appBalance.app.slug,
                protocolName: appBalance.app.displayName,
                protocolLogoURL: appBalance.app.imgUrl,
                healthFactor: nil,
                tokens: tokens)

        case let .appToken(position):
            let token = TokenDTO(
                role: .lpToken,
                symbol: position.symbol,
                name: position.symbol,
                amount: decimal(from: position.balance),
                usdValue: Decimal(abs(position.balanceUSD)),
                chain: Self.chainsById[appBalance.network.chainId],
                contractAddress: position.address,
                debankId: nil,
                coinGeckoId: nil,
                sourceKey: "zapper:\(appBalance.network.chainId):\(position.key ?? position.address)",
                logoURL: appBalance.app.imgUrl,
                category: .defi,
                isVerified: true)
            return PositionDTO(
                positionType: .liquidityPool,
                chain: Self.chainsById[appBalance.network.chainId],
                protocolId: appBalance.app.slug,
                protocolName: appBalance.app.displayName,
                protocolLogoURL: appBalance.app.imgUrl,
                healthFactor: nil,
                tokens: [token])
        }
    }

    private func tokenDTO(
        from token: PositionTokenNode,
        role: TokenRole,
        sourceKey: String,
        chain: Chain?) -> TokenDTO {
        TokenDTO(
            role: role,
            symbol: token.symbol,
            name: token.symbol,
            amount: decimal(from: token.balance),
            usdValue: Decimal(abs(token.balanceUSD)),
            chain: chain,
            contractAddress: token.address,
            debankId: nil,
            coinGeckoId: nil,
            sourceKey: sourceKey,
            logoURL: nil,
            category: .defi,
            isVerified: true)
    }

    private func tokenSourceKey(_ positionKey: String?, token: PositionTokenNode, chainId: Int) -> String {
        let key = positionKey ?? token.address
        return "zapper:\(chainId):\(key):\(token.address):\(token.symbol)"
    }

    private func role(for metaType: String?) -> TokenRole {
        switch metaType {
        case "SUPPLIED":
            .supply
        case "BORROWED":
            .borrow
        case "CLAIMABLE":
            .reward
        case "LOCKED", "VESTING":
            .stake
        default:
            .balance
        }
    }

    private func positionType(from groupLabel: String?) -> PositionType {
        let label = groupLabel?.lowercased() ?? ""
        if label.contains("lend") || label.contains("borrow") {
            return .lending
        }
        if label.contains("stake") {
            return .staking
        }
        if label.contains("farm") {
            return .farming
        }
        if label.contains("pool") || label.contains("liquidity") {
            return .liquidityPool
        }
        return .other
    }

    private func decimal(from string: String) -> Decimal {
        Decimal(string: string).map(abs) ?? 0
    }

    private static let chainIds: [Chain: Int] = [
        .ethereum: 1,
        .polygon: 137,
        .arbitrum: 42161,
        .optimism: 10,
        .base: 8453,
        .bsc: 56,
        .solana: 1_151_111_081,
        .bitcoin: 6_172_014,
        .avalanche: 43114,
        .monad: 143
    ]

    private static let chainsById: [Int: Chain] = Dictionary(
        uniqueKeysWithValues: chainIds.map { ($0.value, $0.key) })
}

public enum ZapperError: Error, LocalizedError, Sendable {
    case invalidResponse
    case rateLimited
    case unauthorized
    case httpError(statusCode: Int)
    case decodingFailed
    case schemaChanged(context: String)
    case graphQLError(String)
    case unsupportedChain(Chain)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Zapper API"
        case .rateLimited:
            "Zapper API rate limit exceeded"
        case .unauthorized:
            "Invalid Zapper API key"
        case let .httpError(code):
            "Zapper API returned HTTP \(code)"
        case .decodingFailed:
            "Failed to parse Zapper API response"
        case let .schemaChanged(ctx):
            "Zapper API schema may have changed: \(ctx)"
        case let .graphQLError(message):
            "Zapper GraphQL error: \(message)"
        case let .unsupportedChain(chain):
            "Zapper does not support explicit chain filter: \(chain.rawValue)"
        }
    }
}
