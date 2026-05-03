import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

final class ZapperMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data?, Int))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        requestHandler = nil
        requests = []
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        do {
            let (data, statusCode) = try Self.requestHandler?(request) ?? (nil, 200)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ZapperMockURLProtocol.self]
    return URLSession(configuration: config)
}

func makeProvider(session: URLSession, baseURL: URL = URL(string: "https://test.local/graphql")!) -> ZapperProvider {
    ZapperProvider(apiKey: "test-key", session: session, baseURL: baseURL)
}

func makeSyncContext(chain: Chain? = nil) -> SyncContext {
    SyncContext(accountId: UUID(), kind: .wallet, addresses: [("0xabc", chain)], exchangeType: nil)
}

func makeSyncContext(addresses: [(String, Chain?)]) -> SyncContext {
    SyncContext(accountId: UUID(), kind: .wallet, addresses: addresses, exchangeType: nil)
}

func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

func graphQLBody(from request: URLRequest) throws -> [String: Any] {
    let body = try requestBody(from: request)
    let json = try JSONSerialization.jsonObject(with: body)
    return try #require(json as? [String: Any])
}

func graphQLVariables(from request: URLRequest) throws -> [String: Any] {
    let body = try graphQLBody(from: request)
    return try #require(body["variables"] as? [String: Any])
}

func requestBody(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw ZapperTestError.unreadableBodyStream
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

enum ZapperTestError: Error {
    case unreadableBodyStream
}

func tokenResponse(
    symbol: String = "ETH",
    tokenAddress: String = "0xeth",
    chainId: Int = 1,
    hasNextPage: Bool = false,
    endCursor: String? = nil) -> [String: Any] {
    [
        "data": [
            "portfolioV2": [
                "tokenBalances": [
                    "byToken": [
                        "edges": [
                            [
                                "node": [
                                    "tokenAddress": tokenAddress,
                                    "name": "Ethereum",
                                    "symbol": symbol,
                                    "balance": 1.5,
                                    "balanceUSD": 3000.0,
                                    "verified": true,
                                    "imgUrlV2": "https://img.example/eth.png",
                                    "network": ["chainId": chainId, "name": "Ethereum"]
                                ] as [String: Any]
                            ] as [String: Any]
                        ],
                        "pageInfo": [
                            "hasNextPage": hasNextPage,
                            "endCursor": endCursor.map { $0 as Any } ?? NSNull()
                        ]
                    ]
                ]
            ]
        ]
    ]
}

func appBalancesResponse(
    positionEdges: [[String: Any]] = [contractPositionEdge(), appTokenPositionEdge()],
    positionHasNextPage: Bool = false,
    positionEndCursor: String? = nil,
    appHasNextPage: Bool = false,
    appEndCursor: String? = nil,
    appEdges: [[String: Any]]? = nil) -> [String: Any] {
    [
        "data": [
            "portfolioV2": [
                "appBalances": [
                    "byApp": [
                        "edges": appEdges ?? [
                            appBalanceEdge(
                                positionEdges: positionEdges,
                                positionHasNextPage: positionHasNextPage,
                                positionEndCursor: positionEndCursor)
                        ],
                        "pageInfo": [
                            "hasNextPage": appHasNextPage,
                            "endCursor": appEndCursor.map { $0 as Any } ?? NSNull()
                        ]
                    ]
                ]
            ]
        ]
    ]
}

func appBalanceEdge(
    positionEdges: [[String: Any]],
    positionHasNextPage: Bool = false,
    positionEndCursor: String? = nil) -> [String: Any] {
    [
        "node": [
            "appId": "aave-v3",
            "balanceUSD": 2500.0,
            "app": appNode(),
            "network": ["chainId": 1, "name": "Ethereum"],
            "positionBalances": [
                "edges": positionEdges,
                "pageInfo": [
                    "hasNextPage": positionHasNextPage,
                    "endCursor": positionEndCursor.map { $0 as Any } ?? NSNull()
                ]
            ]
        ] as [String: Any]
    ]
}

func appNode() -> [String: Any] {
    [
        "slug": "aave-v3",
        "displayName": "Aave V3",
        "imgUrl": "https://img.example/aave.png"
    ]
}

func contractPositionEdge(
    groupId: String? = "lending",
    groupLabel: String? = "Lending",
    tokens: [[String: Any]]? = nil) -> [String: Any] {
    [
        "node": [
            "__typename": "ContractPositionBalance",
            "key": "contract-position",
            "appId": "aave-v3",
            "groupId": groupId.map { $0 as Any } ?? NSNull(),
            "groupLabel": groupLabel.map { $0 as Any } ?? NSNull(),
            "balanceUSD": 1500.0,
            "tokens": tokens ?? [
                tokenWithMetaType("SUPPLIED", address: "0xeth", balance: "1.0", balanceUSD: 2000.0, symbol: "ETH"),
                tokenWithMetaType("BORROWED", address: "0xusdc", balance: "500.0", balanceUSD: 500.0, symbol: "USDC"),
                tokenWithMetaType("CLAIMABLE", address: "0xstk", balance: "3.0", balanceUSD: 30.0, symbol: "stkAAVE")
            ]
        ] as [String: Any]
    ]
}

func tokenWithMetaType(
    _ metaType: String?,
    address: String,
    balance: String,
    balanceUSD: Double,
    symbol: String) -> [String: Any] {
    [
        "metaType": metaType.map { $0 as Any } ?? NSNull(),
        "token": tokenNode(
            address: address,
            balance: balance,
            balanceUSD: balanceUSD,
            symbol: symbol)
    ]
}

func tokenNode(address: String, balance: String, balanceUSD: Double, symbol: String) -> [String: Any] {
    [
        "__typename": "BaseTokenPositionBalance",
        "address": address,
        "balance": balance,
        "balanceUSD": balanceUSD,
        "symbol": symbol,
        "network": "ETHEREUM_MAINNET"
    ]
}

func appTokenPositionEdge(balance: String = "2.0") -> [String: Any] {
    [
        "node": [
            "__typename": "AppTokenPositionBalance",
            "address": "0xlp",
            "balance": balance,
            "balanceUSD": 1000.0,
            "symbol": "aEthUSDC",
            "key": "app-token-position",
            "appId": "aave-v3",
            "groupId": "pool",
            "groupLabel": "Pool",
            "network": "ETHEREUM_MAINNET"
        ] as [String: Any]
    ]
}
