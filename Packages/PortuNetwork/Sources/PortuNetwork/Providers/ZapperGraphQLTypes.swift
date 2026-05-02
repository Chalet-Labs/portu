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
                            decimals
                          }
                        }
                      }
                      ... on AppTokenPositionBalance {
                        address
                        balance
                        balanceUSD
                        symbol
                        decimals
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
                            decimals
                          }
                        }
                      }
                      ... on AppTokenPositionBalance {
                        address
                        balance
                        balanceUSD
                        symbol
                        decimals
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

struct ZapperRequestContext {
    let addresses: [String]
    let chainIds: [Int]?
}

struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

struct PortfolioVariables: Encodable {
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

struct AppPositionVariables: Encodable {
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

struct GraphQLResponse<Data: Decodable>: Decodable {
    let data: Data?
    let errors: [GraphQLError]?

    func payload() throws -> Data {
        if let errors, !errors.isEmpty {
            throw ZapperError.graphQLError(errors.map(\.message).joined(separator: "; "))
        }
        guard let data else {
            throw ZapperError.decodingFailed
        }
        return data
    }
}

struct GraphQLError: Decodable {
    let message: String
}

struct TokenBalancesData: Decodable {
    let portfolioV2: TokenBalancesPortfolio
}

struct TokenBalancesPortfolio: Decodable {
    let tokenBalances: TokenBalances
}

struct TokenBalances: Decodable {
    let byToken: TokenBalanceConnection
}

struct TokenBalanceConnection: Decodable {
    let edges: [TokenBalanceEdge]
    let pageInfo: PageInfo
}

struct TokenBalanceEdge: Decodable {
    let node: TokenBalanceNode
}

struct TokenBalanceNode: Decodable {
    let tokenAddress: String
    let name: String
    let symbol: String
    let balance: Double
    let balanceUSD: Double
    let verified: Bool
    let imgUrlV2: String?
    let network: NetworkObject
}

struct AppBalancesData: Decodable {
    let portfolioV2: AppBalancesPortfolio
}

struct AppBalancesPortfolio: Decodable {
    let appBalances: AppBalances
}

struct AppBalances: Decodable {
    let byApp: AppBalanceConnection
}

struct AppBalanceConnection: Decodable {
    let edges: [AppBalanceEdge]
    let pageInfo: PageInfo
}

struct AppBalanceEdge: Decodable {
    let node: AppBalanceNode
}

struct AppBalanceNode: Decodable {
    let appId: String
    let balanceUSD: Double
    let app: ZapperApp
    let network: NetworkObject
    let positionBalances: AnyPositionBalanceConnection
}

struct ZapperApp: Decodable {
    let slug: String
    let displayName: String
    let imgUrl: String?
}

struct AnyPositionBalanceConnection: Decodable {
    let edges: [AnyPositionBalanceEdge]
    let pageInfo: PageInfo
}

struct AnyPositionBalanceEdge: Decodable {
    let node: AnyPositionBalance
}

enum AnyPositionBalance: Decodable {
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

struct ContractPositionBalance: Decodable {
    let key: String?
    let appId: String
    let groupId: String?
    let groupLabel: String?
    let balanceUSD: Double
    let tokens: [TokenWithMetaType]
}

struct TokenWithMetaType: Decodable {
    let metaType: String?
    let token: PositionTokenNode
}

struct PositionTokenNode: Decodable {
    let address: String
    let network: String
    let balance: String
    let balanceUSD: Double
    let symbol: String
    let decimals: Double
}

struct AppTokenPositionBalance: Decodable {
    let address: String
    let balance: String
    let balanceUSD: Double
    let symbol: String
    let decimals: Double
    let key: String?
    let appId: String
    let groupId: String?
    let groupLabel: String?
    let network: String
}

struct NetworkObject: Decodable {
    let chainId: Int
    let name: String
}

struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}
