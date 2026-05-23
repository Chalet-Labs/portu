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

    static let tokenPriceTicksQuery = """
    query PortuTokenPriceTicks($address: Address!, $chainId: Int!, $currency: Currency!, $timeFrame: TimeFrame!) {
      fungibleTokenV2(address: $address, chainId: $chainId) {
        priceData {
          priceTicks(currency: $currency, timeFrame: $timeFrame) {
            close
            timestamp
          }
        }
      }
    }
    """

    static let tokenPriceBatchQuery = """
    query PortuTokenPriceBatch($tokens: [FungibleTokenInputV2!]!) {
      fungibleTokenBatchV2(tokens: $tokens) {
        address
        priceData {
          price
          priceChange24h
        }
      }
    }
    """
}
