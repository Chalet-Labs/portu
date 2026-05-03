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
        var allPositions: [PositionDTO] = []
        for requestContext in try makeRequestContexts(from: context) {
            try await allPositions.append(contentsOf: fetchBalances(requestContext: requestContext))
        }

        return allPositions
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        var allPositions: [PositionDTO] = []
        for requestContext in try makeRequestContexts(from: context) {
            try await allPositions.append(contentsOf: fetchDeFiPositions(requestContext: requestContext))
        }

        return allPositions
    }

    private func fetchBalances(requestContext: ZapperRequestContext) async throws -> [PositionDTO] {
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
            try allPositions.append(contentsOf: connection.edges.map {
                try position(from: $0.node)
            })

            after = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while after != nil

        return allPositions
    }

    private func fetchDeFiPositions(requestContext: ZapperRequestContext) async throws -> [PositionDTO] {
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
                try await allPositions.append(contentsOf: positions(from: edge.node, requestContext: requestContext))
            }

            after = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while after != nil

        return allPositions
    }

    private func positions(from appBalance: AppBalanceNode, requestContext: ZapperRequestContext) async throws -> [PositionDTO] {
        var positionEdges = appBalance.positionBalances.edges
        if appBalance.positionBalances.pageInfo.hasNextPage {
            let extraEdges = try await fetchRemainingPositionEdges(
                requestContext: requestContext,
                appSlug: appBalance.app.slug,
                after: appBalance.positionBalances.pageInfo.endCursor)
            positionEdges.append(contentsOf: extraEdges)
        }

        var positions: [PositionDTO] = []
        for edge in positionEdges {
            if let position = try position(from: edge.node, appBalance: appBalance) {
                positions.append(position)
            }
        }
        return positions
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
                throw ZapperError.schemaChanged(context: "Missing app while paginating positions for \(appSlug)")
            }
            let connection = appBalance.positionBalances
            allEdges.append(contentsOf: connection.edges)
            after = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        }

        return allEdges
    }

    private func makeRequestContexts(from context: SyncContext) throws -> [ZapperRequestContext] {
        var unfilteredAddresses: [String] = []
        var addressesByChainId: [Int: [String]] = [:]

        for (address, chain) in context.addresses {
            guard let chain else {
                unfilteredAddresses.append(address)
                continue
            }
            guard let chainId = Self.chainIds[chain] else {
                throw ZapperError.unsupportedChain(chain)
            }
            addressesByChainId[chainId, default: []].append(address)
        }

        var contexts: [ZapperRequestContext] = []
        if !unfilteredAddresses.isEmpty {
            contexts.append(ZapperRequestContext(addresses: unfilteredAddresses, chainIds: nil))
        }
        contexts.append(contentsOf: addressesByChainId.keys.sorted().map {
            ZapperRequestContext(addresses: addressesByChainId[$0] ?? [], chainIds: [$0])
        })

        return contexts
    }

    private func performGraphQL<Data: Decodable & Sendable>(
        query: String,
        variables: some Encodable & Sendable) async throws -> GraphQLResponse<Data> {
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
            let response = try decoder.decode(GraphQLResponse<Data>.self, from: data)
            if let message = response.partialErrorMessage {
                Self.logger.warning("Zapper GraphQL returned partial data: \(message, privacy: .public)")
            }
            return response
        case 429:
            throw ZapperError.rateLimited
        case 401, 403:
            throw ZapperError.unauthorized
        default:
            throw ZapperError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func position(from node: TokenBalanceNode) throws -> PositionDTO {
        let chain = try chain(for: node.network.chainId)
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

    private func position(from node: AnyPositionBalance, appBalance: AppBalanceNode) throws -> PositionDTO? {
        let chain = try chain(for: appBalance.network.chainId)
        switch node {
        case let .contract(position):
            let tokens = try position.tokens.map {
                try tokenDTO(
                    from: $0.token,
                    role: role(for: $0.metaType),
                    sourceKey: tokenSourceKey(position.key, token: $0.token, chainId: appBalance.network.chainId),
                    chain: chain)
            }
            guard !tokens.isEmpty else { return nil }
            return PositionDTO(
                positionType: positionType(groupId: position.groupId, groupLabel: position.groupLabel),
                chain: chain,
                protocolId: appBalance.app.slug,
                protocolName: appBalance.app.displayName,
                protocolLogoURL: appBalance.app.imgUrl,
                healthFactor: nil,
                tokens: tokens)

        case let .appToken(position):
            let token = try TokenDTO(
                role: .lpToken,
                symbol: position.symbol,
                name: position.symbol,
                amount: decimal(from: position.balance),
                usdValue: Decimal(abs(position.balanceUSD)),
                chain: chain,
                contractAddress: position.address,
                debankId: nil,
                coinGeckoId: nil,
                sourceKey: "zapper:\(appBalance.network.chainId):\(position.key ?? position.address)",
                logoURL: appBalance.app.imgUrl,
                category: .defi,
                isVerified: true)
            return PositionDTO(
                positionType: .liquidityPool,
                chain: chain,
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
        chain: Chain) throws -> TokenDTO {
        try TokenDTO(
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

    private func role(for metaType: String?) throws -> TokenRole {
        guard let metaType else { return .balance }
        switch metaType.uppercased() {
        case "SUPPLIED":
            return .supply
        case "BORROWED":
            return .borrow
        case "CLAIMABLE":
            return .reward
        case "LOCKED", "VESTING":
            return .stake
        default:
            throw ZapperError.schemaChanged(context: "Unknown token metaType: \(metaType)")
        }
    }

    private func positionType(groupId: String?, groupLabel: String?) -> PositionType {
        let label = (groupId ?? groupLabel)?.lowercased() ?? ""
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

    private func decimal(from string: String) throws -> Decimal {
        guard let value = Decimal(string: string, locale: Self.posixLocale) else {
            throw ZapperError.schemaChanged(context: "Invalid decimal balance: \(string)")
        }
        return abs(value)
    }

    private func chain(for chainId: Int) throws -> Chain {
        guard let chain = Self.chainsById[chainId] else {
            throw ZapperError.schemaChanged(context: "Unknown Zapper chainId: \(chainId)")
        }
        return chain
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

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
