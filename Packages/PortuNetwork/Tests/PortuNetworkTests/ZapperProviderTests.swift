import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

// MARK: - Mock URL Protocol

final class ZapperMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data?, Int))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

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

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ZapperMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeProvider(session: URLSession, baseURL: URL = URL(string: "https://test.local/graphql")!) -> ZapperProvider {
    ZapperProvider(apiKey: "test-key", session: session, baseURL: baseURL)
}

private func makeSyncContext(chain: Chain? = nil) -> SyncContext {
    SyncContext(accountId: UUID(), kind: .wallet, addresses: [("0xabc", chain)], exchangeType: nil)
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private func graphQLBody(from request: URLRequest) throws -> [String: Any] {
    let body = try requestBody(from: request)
    let json = try JSONSerialization.jsonObject(with: body)
    return try #require(json as? [String: Any])
}

private func graphQLVariables(from request: URLRequest) throws -> [String: Any] {
    let body = try graphQLBody(from: request)
    return try #require(body["variables"] as? [String: Any])
}

private func requestBody(from request: URLRequest) throws -> Data {
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
            throw stream.streamError ?? ZapperTestError.unreadableBodyStream
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

private enum ZapperTestError: Error {
    case unreadableBodyStream
}

private func tokenResponse(
    symbol: String = "ETH",
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
                                    "tokenAddress": "0xeth",
                                    "name": "Ethereum",
                                    "symbol": symbol,
                                    "balance": 1.5,
                                    "balanceUSD": 3000.0,
                                    "verified": true,
                                    "imgUrlV2": "https://img.example/eth.png",
                                    "network": ["chainId": 1, "name": "Ethereum"]
                                ] as [String: Any]
                            ] as [String: Any]
                        ],
                        "pageInfo": [
                            "hasNextPage": hasNextPage,
                            "endCursor": endCursor as Any
                        ]
                    ]
                ]
            ]
        ]
    ]
}

private func appBalancesResponse() -> [String: Any] {
    [
        "data": [
            "portfolioV2": [
                "appBalances": [
                    "byApp": [
                        "edges": [
                            [
                                "node": [
                                    "appId": "aave-v3",
                                    "balanceUSD": 2500.0,
                                    "app": appNode(),
                                    "network": ["chainId": 1, "name": "Ethereum"],
                                    "positionBalances": [
                                        "edges": [contractPositionEdge(), appTokenPositionEdge()],
                                        "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]
                                    ]
                                ] as [String: Any]
                            ] as [String: Any]
                        ],
                        "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]
                    ]
                ]
            ]
        ]
    ]
}

private func appNode() -> [String: Any] {
    [
        "slug": "aave-v3",
        "displayName": "Aave V3",
        "imgUrl": "https://img.example/aave.png"
    ]
}

private func contractPositionEdge() -> [String: Any] {
    [
        "node": [
            "__typename": "ContractPositionBalance",
            "key": "contract-position",
            "appId": "aave-v3",
            "groupId": "lending",
            "groupLabel": "Lending",
            "balanceUSD": 1500.0,
            "tokens": [
                tokenWithMetaType("SUPPLIED", address: "0xeth", balance: "1.0", balanceUSD: 2000.0, symbol: "ETH"),
                tokenWithMetaType("BORROWED", address: "0xusdc", balance: "500.0", balanceUSD: 500.0, symbol: "USDC"),
                tokenWithMetaType("CLAIMABLE", address: "0xstk", balance: "3.0", balanceUSD: 30.0, symbol: "stkAAVE")
            ]
        ] as [String: Any]
    ]
}

private func tokenWithMetaType(
    _ metaType: String,
    address: String,
    balance: String,
    balanceUSD: Double,
    symbol: String) -> [String: Any] {
    [
        "metaType": metaType,
        "token": tokenNode(
            address: address,
            balance: balance,
            balanceUSD: balanceUSD,
            symbol: symbol)
    ]
}

private func tokenNode(address: String, balance: String, balanceUSD: Double, symbol: String) -> [String: Any] {
    [
        "__typename": "BaseTokenPositionBalance",
        "address": address,
        "balance": balance,
        "balanceUSD": balanceUSD,
        "symbol": symbol,
        "decimals": symbol == "USDC" ? 6.0 : 18.0,
        "network": "ETHEREUM_MAINNET"
    ]
}

private func appTokenPositionEdge() -> [String: Any] {
    [
        "node": [
            "__typename": "AppTokenPositionBalance",
            "address": "0xlp",
            "balance": "2.0",
            "balanceUSD": 1000.0,
            "symbol": "aEthUSDC",
            "decimals": 18.0,
            "key": "app-token-position",
            "appId": "aave-v3",
            "groupId": "pool",
            "groupLabel": "Pool",
            "network": "ETHEREUM_MAINNET"
        ] as [String: Any]
    ]
}

// MARK: - Tests

@Suite(.serialized)
struct ZapperProviderTests {
    let session = makeMockSession()

    init() {
        ZapperMockURLProtocol.requestHandler = nil
        ZapperMockURLProtocol.requests = []
    }

    @Test
    func `fetchBalances sends GraphQL POST with API key and variables`() async throws {
        ZapperMockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://test.local/graphql")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "x-zapper-api-key") == "test-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let variables = try graphQLVariables(from: request)
            #expect(variables["addresses"] as? [String] == ["0xabc"])
            #expect(variables["chainIds"] == nil)
            #expect(variables["first"] as? Int == 100)
            #expect(variables["after"] is NSNull)
            return try (jsonData(tokenResponse()), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchBalances(context: makeSyncContext())

        #expect(results.count == 1)
    }

    @Test
    func `fetchBalances decodes token balances into idle positions`() async throws {
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(tokenResponse(symbol: "ETH")), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchBalances(context: makeSyncContext())

        #expect(results.count == 1)
        #expect(results[0].positionType == .idle)
        #expect(results[0].chain == .ethereum)
        let token = try #require(results[0].tokens.first)
        #expect(token.role == .balance)
        #expect(token.symbol == "ETH")
        #expect(token.name == "Ethereum")
        #expect(token.amount == Decimal(string: "1.5"))
        #expect(token.usdValue == Decimal(3000))
        #expect(token.contractAddress == "0xeth")
        #expect(token.sourceKey == "zapper:1:0xeth")
        #expect(token.logoURL == "https://img.example/eth.png")
        #expect(token.isVerified)
    }

    @Test
    func `fetchBalances paginates token balances until final page`() async throws {
        var callCount = 0
        ZapperMockURLProtocol.requestHandler = { request in
            callCount += 1
            let variables = try graphQLVariables(from: request)
            if callCount == 1 {
                #expect(variables["after"] is NSNull)
                return try (jsonData(tokenResponse(symbol: "ETH", hasNextPage: true, endCursor: "cursor-1")), 200)
            }
            #expect(variables["after"] as? String == "cursor-1")
            return try (jsonData(tokenResponse(symbol: "DAI")), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchBalances(context: makeSyncContext())

        #expect(callCount == 2)
        #expect(results.map { $0.tokens[0].symbol } == ["ETH", "DAI"])
    }

    @Test
    func `graphql errors throw graphQLError`() async throws {
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(["errors": [["message": "bad query"]]]), 200)
        }

        let provider = makeProvider(session: session)
        do {
            _ = try await provider.fetchBalances(context: makeSyncContext())
            Issue.record("Expected ZapperError.graphQLError")
        } catch let ZapperError.graphQLError(message) {
            #expect(message.contains("bad query"))
        }
    }

    @Test
    func `http errors preserve existing mappings`() async throws {
        let cases: [(Int, (ZapperError) -> Bool)] = [
            (401, { if case .unauthorized = $0 { true } else { false } }),
            (403, { if case .unauthorized = $0 { true } else { false } }),
            (429, { if case .rateLimited = $0 { true } else { false } }),
            (500, { if case .httpError(statusCode: 500) = $0 { true } else { false } })
        ]

        for (statusCode, matches) in cases {
            ZapperMockURLProtocol.requestHandler = { _ in (nil, statusCode) }
            let provider = makeProvider(session: session)
            do {
                _ = try await provider.fetchBalances(context: makeSyncContext())
                Issue.record("Expected HTTP error for \(statusCode)")
            } catch let error as ZapperError {
                #expect(matches(error))
            }
        }
    }

    @Test
    func `explicit chain filter sends matching chain id`() async throws {
        ZapperMockURLProtocol.requestHandler = { request in
            let variables = try graphQLVariables(from: request)
            #expect(variables["chainIds"] as? [Int] == [42161])
            return try (jsonData(tokenResponse()), 200)
        }

        let provider = makeProvider(session: session)
        _ = try await provider.fetchBalances(context: makeSyncContext(chain: .arbitrum))
    }

    @Test
    func `unsupported explicit chain throws unsupportedChain`() async throws {
        let provider = makeProvider(session: session)
        do {
            _ = try await provider.fetchBalances(context: makeSyncContext(chain: .katana))
            Issue.record("Expected unsupported chain")
        } catch let ZapperError.unsupportedChain(chain) {
            #expect(chain == .katana)
            #expect(ZapperMockURLProtocol.requests.isEmpty)
        }
    }

    @Test
    func `fetchDeFiPositions maps contract tokens by meta type`() async throws {
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(appBalancesResponse()), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchDeFiPositions(context: makeSyncContext())
        let contract = try #require(results.first { $0.tokens.contains { $0.symbol == "USDC" } })

        #expect(contract.positionType == .lending)
        #expect(contract.protocolId == "aave-v3")
        #expect(contract.protocolName == "Aave V3")
        #expect(contract.protocolLogoURL == "https://img.example/aave.png")
        #expect(contract.chain == .ethereum)
        #expect(contract.tokens.map(\.role) == [.supply, .borrow, .reward])
    }

    @Test
    func `fetchDeFiPositions maps app token position to lp token`() async throws {
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(appBalancesResponse()), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchDeFiPositions(context: makeSyncContext())
        let lpPosition = try #require(results.first { $0.tokens.first?.symbol == "aEthUSDC" })
        let token = try #require(lpPosition.tokens.first)

        #expect(lpPosition.positionType == .liquidityPool)
        #expect(token.role == .lpToken)
        #expect(token.symbol == "aEthUSDC")
        #expect(token.amount == Decimal(2))
        #expect(token.usdValue == Decimal(1000))
        #expect(token.sourceKey == "zapper:1:app-token-position")
    }

    @Test
    func `live smoke fetches balances and defi positions when explicitly enabled`() async throws {
        let env = ProcessInfo.processInfo.environment
        guard
            env["PORTU_ZAPPER_LIVE_TESTS"] == "1",
            let apiKey = env["ZAPPER_API_KEY"],
            !apiKey.isEmpty
        else { return }

        let address = env["ZAPPER_SMOKE_ADDRESS"] ?? "0x00000000219ab540356cBB839Cbe05303d7705Fa"
        let context = SyncContext(accountId: UUID(), kind: .wallet, addresses: [(address, .ethereum)], exchangeType: nil)
        let provider = ZapperProvider(apiKey: apiKey)
        _ = try await provider.fetchBalances(context: context)
        _ = try await provider.fetchDeFiPositions(context: context)
    }
}
