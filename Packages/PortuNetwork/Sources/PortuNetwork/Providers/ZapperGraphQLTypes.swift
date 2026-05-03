import Foundation

// MARK: - GraphQL Queries

extension ZapperProvider {
    static let tokenBalancesQuery = """
    query PortuTokenBalances($addresses: [Address!]!, $chainIds: [Int!], $first: Int!, $after: String) {
      portfolioV2(addresses: $addresses, chainIds: $chainIds) {
        tokenBalances {
          byToken(first: $first, after: $after) {
            edges {
              node {
                tokenAddress
                name
                symbol
                balance
                balanceUSD
                verified
                imgUrlV2
                network {
                  chainId
                  name
                }
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      }
    }
    """

    static let appBalancesQuery = """
    query PortuAppBalances($addresses: [Address!]!, $chainIds: [Int!], $first: Int!, $after: String) {
      portfolioV2(addresses: $addresses, chainIds: $chainIds) {
        appBalances {
          byApp(first: $first, after: $after) {
            edges {
              node {
                appId
                balanceUSD
                app {
                  slug
                  displayName
                  imgUrl
                }
                network {
                  chainId
                  name
                }
                positionBalances(first: 100) {
                  edges {
                    node {
                      __typename
                      ... on ContractPositionBalance {
                        key
                        appId
                        groupId
                        groupLabel
                        balanceUSD
                        tokens {
                          metaType
                          token {
                            __typename
                            address
                            network
                            balance
                            balanceUSD
                            symbol
                          }
                        }
                      }
                      ... on AppTokenPositionBalance {
                        address
                        balance
                        balanceUSD
                        symbol
                        key
                        appId
                        groupId
                        groupLabel
                        network
                      }
                    }
                  }
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                }
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      }
    }
    """

    static let appPositionBalancesQuery = """
    query PortuAppPositionBalances(
      $addresses: [Address!]!,
      $chainIds: [Int!],
      $appSlug: String!,
      $first: Int!,
      $after: String
    ) {
      portfolioV2(addresses: $addresses, chainIds: $chainIds) {
        appBalances {
          byApp(first: 1, filters: { appSlugs: [$appSlug] }) {
            edges {
              node {
                appId
                balanceUSD
                app {
                  slug
                  displayName
                  imgUrl
                }
                network {
                  chainId
                  name
                }
                positionBalances(first: $first, after: $after) {
                  edges {
                    node {
                      __typename
                      ... on ContractPositionBalance {
                        key
                        appId
                        groupId
                        groupLabel
                        balanceUSD
                        tokens {
                          metaType
                          token {
                            __typename
                            address
                            network
                            balance
                            balanceUSD
                            symbol
                          }
                        }
                      }
                      ... on AppTokenPositionBalance {
                        address
                        balance
                        balanceUSD
                        symbol
                        key
                        appId
                        groupId
                        groupLabel
                        network
                      }
                    }
                  }
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                }
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      }
    }
    """
}

// MARK: - Request Types

// swiftformat:disable redundantSendable

struct ZapperRequestContext: Sendable {
    let addresses: [String]
    let chainIds: [Int]?
}

struct GraphQLRequest<Variables: Encodable & Sendable>: Encodable, Sendable {
    let query: String
    let variables: Variables
}

struct PortfolioVariables: Encodable, Sendable {
    let addresses: [String]
    let chainIds: [Int]?
    let first: Int
    let after: String?

    enum CodingKeys: CodingKey {
        case addresses
        case chainIds
        case first
        case after
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(addresses, forKey: .addresses)
        try container.encodeIfPresent(chainIds, forKey: .chainIds)
        try container.encode(first, forKey: .first)
        if let after {
            try container.encode(after, forKey: .after)
        } else {
            try container.encodeNil(forKey: .after)
        }
    }
}

struct AppPositionVariables: Encodable, Sendable {
    let addresses: [String]
    let chainIds: [Int]?
    let appSlug: String
    let first: Int
    let after: String?

    enum CodingKeys: CodingKey {
        case addresses
        case chainIds
        case appSlug
        case first
        case after
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(addresses, forKey: .addresses)
        try container.encodeIfPresent(chainIds, forKey: .chainIds)
        try container.encode(appSlug, forKey: .appSlug)
        try container.encode(first, forKey: .first)
        if let after {
            try container.encode(after, forKey: .after)
        } else {
            try container.encodeNil(forKey: .after)
        }
    }
}

// MARK: - Response Types

struct GraphQLResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload?
    let errors: [GraphQLError]?

    func payload() throws -> Payload {
        if let data {
            return data
        }
        guard let errors, !errors.isEmpty else {
            throw ZapperError.decodingFailed
        }
        if errors.contains(where: \.isAuthorizationError) {
            throw ZapperError.unauthorized
        }
        if errors.contains(where: \.isRateLimitError) {
            throw ZapperError.rateLimited
        }
        throw ZapperError.graphQLError(errors.map(\.message).joined(separator: "; "))
    }

    var partialErrorMessage: String? {
        guard data != nil, let errors, !errors.isEmpty else { return nil }
        return errors.map(\.message).joined(separator: "; ")
    }
}

struct GraphQLError: Decodable, Sendable {
    static let authorizationCodes: Set<String> = ["UNAUTHENTICATED", "UNAUTHORIZED", "FORBIDDEN"]
    static let rateLimitCodes: Set<String> = ["RATE_LIMITED", "THROTTLED", "TOO_MANY_REQUESTS"]

    let message: String
    let extensions: GraphQLErrorExtensions?

    var isAuthorizationError: Bool {
        guard let code = extensions?.code?.uppercased() else { return false }
        return Self.authorizationCodes.contains(code)
    }

    var isRateLimitError: Bool {
        guard let code = extensions?.code?.uppercased() else { return false }
        return Self.rateLimitCodes.contains(code)
    }
}

struct GraphQLErrorExtensions: Decodable, Sendable {
    let code: String?
}

struct TokenBalancesData: Decodable, Sendable {
    let portfolioV2: TokenBalancesPortfolio
}

struct TokenBalancesPortfolio: Decodable, Sendable {
    let tokenBalances: TokenBalances
}

struct TokenBalances: Decodable, Sendable {
    let byToken: TokenBalanceConnection
}

struct TokenBalanceConnection: Decodable, Sendable {
    let edges: [TokenBalanceEdge?]?
    let pageInfo: PageInfo
}

struct TokenBalanceEdge: Decodable, Sendable {
    let node: TokenBalanceNode?
}

struct TokenBalanceNode: Decodable, Sendable {
    let tokenAddress: String
    let name: String
    let symbol: String
    let balance: Double
    let balanceUSD: Double
    let verified: Bool
    let imgUrlV2: String?
    let network: NetworkObject
}

struct AppBalancesData: Decodable, Sendable {
    let portfolioV2: AppBalancesPortfolio
}

struct AppBalancesPortfolio: Decodable, Sendable {
    let appBalances: AppBalances
}

struct AppBalances: Decodable, Sendable {
    let byApp: AppBalanceConnection
}

struct AppBalanceConnection: Decodable, Sendable {
    let edges: [AppBalanceEdge?]?
    let pageInfo: PageInfo
}

struct AppBalanceEdge: Decodable, Sendable {
    let node: AppBalanceNode?
}

struct AppBalanceNode: Decodable, Sendable {
    let appId: String
    let balanceUSD: Double
    let app: ZapperApp
    let network: NetworkObject
    let positionBalances: AnyPositionBalanceConnection
}

struct ZapperApp: Decodable, Sendable {
    let slug: String
    let displayName: String
    let imgUrl: String?
}

struct AnyPositionBalanceConnection: Decodable, Sendable {
    let edges: [AnyPositionBalanceEdge?]?
    let pageInfo: PageInfo
}

struct AnyPositionBalanceEdge: Decodable, Sendable {
    let node: AnyPositionBalance?
}

enum AnyPositionBalance: Decodable, Sendable {
    case contract(ContractPositionBalance)
    case appToken(AppTokenPositionBalance)

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typename = try container.decode(String.self, forKey: .typename)
        switch typename {
        case "ContractPositionBalance":
            self = try .contract(ContractPositionBalance(from: decoder))
        case "AppTokenPositionBalance":
            self = try .appToken(AppTokenPositionBalance(from: decoder))
        default:
            throw ZapperError.schemaChanged(context: "Unknown position balance type: \(typename)")
        }
    }
}

struct ContractPositionBalance: Decodable, Sendable {
    let key: String?
    let appId: String
    let groupId: String?
    let groupLabel: String?
    let balanceUSD: Double
    let tokens: [TokenWithMetaType?]?
}

struct TokenWithMetaType: Decodable, Sendable {
    let metaType: String?
    let token: PositionTokenNode?
}

struct PositionTokenNode: Decodable, Sendable {
    let address: String
    let network: String
    let balance: String
    let balanceUSD: Double
    let symbol: String
}

struct AppTokenPositionBalance: Decodable, Sendable {
    let address: String
    let balance: String
    let balanceUSD: Double
    let symbol: String
    let key: String?
    let appId: String
    let groupId: String?
    let groupLabel: String?
    let network: String
}

struct NetworkObject: Decodable, Sendable {
    let chainId: Int
    let name: String
}

struct PageInfo: Decodable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
}

// swiftformat:enable redundantSendable
