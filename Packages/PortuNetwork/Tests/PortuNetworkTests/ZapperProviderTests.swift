import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

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
    func `fetchBalances partitions mixed explicit chain addresses`() async throws {
        var capturedVariables: [[String: Any]] = []
        ZapperMockURLProtocol.requestHandler = { request in
            let variables = try graphQLVariables(from: request)
            capturedVariables.append(variables)
            let chainIds = try #require(variables["chainIds"] as? [Int])
            let chainId = try #require(chainIds.first)
            return try (
                jsonData(tokenResponse(symbol: "TOKEN-\(chainId)", tokenAddress: "token-\(chainId)", chainId: chainId)),
                200)
        }

        let context = makeSyncContext(addresses: [
            ("0xabc", .ethereum),
            ("Sol123", .solana)
        ])
        let provider = makeProvider(session: session)
        let results = try await provider.fetchBalances(context: context)

        #expect(capturedVariables.count == 2)
        #expect(capturedVariables[0]["addresses"] as? [String] == ["0xabc"])
        #expect(capturedVariables[0]["chainIds"] as? [Int] == [1])
        #expect(capturedVariables[1]["addresses"] as? [String] == ["Sol123"])
        #expect(capturedVariables[1]["chainIds"] as? [Int] == [1_151_111_081])
        #expect(results.map(\.chain) == [.ethereum, .solana])
    }

    @Test
    func `fetchBalances aggregates same explicit chain addresses`() async throws {
        ZapperMockURLProtocol.requestHandler = { request in
            let variables = try graphQLVariables(from: request)
            #expect(variables["addresses"] as? [String] == ["0x1", "0x2"])
            #expect(variables["chainIds"] as? [Int] == [8453])
            return try (jsonData(tokenResponse(chainId: 8453)), 200)
        }

        let context = makeSyncContext(addresses: [
            ("0x1", .base),
            ("0x2", .base)
        ])
        let provider = makeProvider(session: session)
        _ = try await provider.fetchBalances(context: context)

        #expect(ZapperMockURLProtocol.requests.count == 1)
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
    func `graphql partial data returns decoded positions`() async throws {
        ZapperMockURLProtocol.requestHandler = { _ in
            var response = tokenResponse()
            response["errors"] = [["message": "Polygon resolver unavailable"]]
            return try (jsonData(response), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchBalances(context: makeSyncContext())

        #expect(results.count == 1)
        #expect(results[0].tokens.first?.symbol == "ETH")
    }

    @Test
    func `graphql auth and rate limit codes map to provider errors`() async throws {
        let cases: [(String, (ZapperError) -> Bool)] = [
            ("UNAUTHENTICATED", { if case .unauthorized = $0 { true } else { false } }),
            ("RATE_LIMITED", { if case .rateLimited = $0 { true } else { false } })
        ]

        for (code, matches) in cases {
            ZapperMockURLProtocol.requestHandler = { _ in
                let response = ["errors": [["message": code, "extensions": ["code": code]]]]
                return try (jsonData(response), 200)
            }
            let provider = makeProvider(session: session)
            do {
                _ = try await provider.fetchBalances(context: makeSyncContext())
                Issue.record("Expected mapped GraphQL error for \(code)")
            } catch let error as ZapperError {
                #expect(matches(error))
            }
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
    func `fetchDeFiPositions paginates nested position balances`() async throws {
        var callCount = 0
        ZapperMockURLProtocol.requestHandler = { request in
            callCount += 1
            let variables = try graphQLVariables(from: request)
            if callCount == 1 {
                #expect(variables["after"] is NSNull)
                return try (jsonData(appBalancesResponse(
                    positionEdges: [contractPositionEdge()],
                    positionHasNextPage: true,
                    positionEndCursor: "pos-cursor")), 200)
            }
            #expect(variables["appSlug"] as? String == "aave-v3")
            #expect(variables["first"] as? Int == 100)
            #expect(variables["after"] as? String == "pos-cursor")
            return try (jsonData(appBalancesResponse(positionEdges: [appTokenPositionEdge()])), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchDeFiPositions(context: makeSyncContext())

        #expect(callCount == 2)
        #expect(results.count == 2)
        #expect(results.flatMap(\.tokens).map(\.symbol).contains("aEthUSDC"))
    }

    @Test
    func `missing app during nested pagination throws schemaChanged`() async throws {
        var callCount = 0
        ZapperMockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return try (jsonData(appBalancesResponse(
                    positionEdges: [contractPositionEdge()],
                    positionHasNextPage: true,
                    positionEndCursor: "pos-cursor")), 200)
            }
            return try (jsonData(appBalancesResponse(appEdges: [])), 200)
        }

        let provider = makeProvider(session: session)
        do {
            _ = try await provider.fetchDeFiPositions(context: makeSyncContext())
            Issue.record("Expected schemaChanged")
        } catch let ZapperError.schemaChanged(context) {
            #expect(context.contains("Missing app"))
        }
    }

    @Test
    func `unknown position typename throws schemaChanged`() async throws {
        let unknownEdge = ["node": ["__typename": "FuturePositionBalance"]]
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(appBalancesResponse(positionEdges: [unknownEdge])), 200)
        }

        let provider = makeProvider(session: session)
        do {
            _ = try await provider.fetchDeFiPositions(context: makeSyncContext())
            Issue.record("Expected schemaChanged")
        } catch let ZapperError.schemaChanged(context) {
            #expect(context.contains("FuturePositionBalance"))
        }
    }

    @Test
    func `invalid decimal balance throws schemaChanged`() async throws {
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(appBalancesResponse(positionEdges: [appTokenPositionEdge(balance: "not-a-decimal")])), 200)
        }

        let provider = makeProvider(session: session)
        do {
            _ = try await provider.fetchDeFiPositions(context: makeSyncContext())
            Issue.record("Expected schemaChanged")
        } catch let ZapperError.schemaChanged(context) {
            #expect(context.contains("Invalid decimal balance"))
        }
    }

    @Test
    func `unknown contract token meta type throws schemaChanged`() async throws {
        let token = tokenWithMetaType("DEBT", address: "0xdebt", balance: "1", balanceUSD: 1, symbol: "DEBT")
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(appBalancesResponse(positionEdges: [contractPositionEdge(tokens: [token])])), 200)
        }

        let provider = makeProvider(session: session)
        do {
            _ = try await provider.fetchDeFiPositions(context: makeSyncContext())
            Issue.record("Expected schemaChanged")
        } catch let ZapperError.schemaChanged(context) {
            #expect(context.contains("metaType"))
        }
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
