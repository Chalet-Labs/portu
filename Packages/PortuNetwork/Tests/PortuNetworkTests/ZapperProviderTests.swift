import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

// MARK: - Mock URL Protocol

final class ZapperMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.mockStatusCode,
            httpVersion: nil,
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = Self.mockData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ZapperMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeProvider(session: URLSession) -> ZapperProvider {
    ZapperProvider(apiKey: "test-key", session: session, baseURL: URL(string: "https://test.local/v2")!)
}

private func makeSyncContext() -> SyncContext {
    SyncContext(accountId: UUID(), kind: .wallet, addresses: [("0xabc", nil)], exchangeType: nil)
}

private func validTokenJSON(
    symbol: String = "ETH", name: String = "Ethereum",
    balance: Double = 1.5, balanceUSD: Double = 3000.0) -> [String: Any] {
    [
        "symbol": symbol, "name": name,
        "balance": balance, "balanceUSD": balanceUSD,
        "network": "ethereum"
    ]
}

private func validAppPositionJSON(
    appId: String = "aave", appName: String = "Aave", type: String = "lending") -> [String: Any] {
    [
        "appId": appId,
        "appName": appName,
        "type": type,
        "network": "ethereum",
        "tokens": [
            [
                "symbol": "ETH", "name": "Ethereum",
                "balance": 1.0, "balanceUSD": 2000.0, "type": "supply"
            ] as [String: Any]
        ] as [[String: Any]]
    ]
}

// MARK: - Tests

@Suite(.serialized)
struct ZapperProviderTests {
    let session = makeMockSession()

    // MARK: Envelope Handling

    struct EnvelopeTests {
        let session = makeMockSession()

        @Test
        func `parseJSONArray unwraps envelope format`() async throws {
            let items: [[String: Any]] = [validTokenJSON()]
            let envelope: [String: Any] = ["data": items]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: envelope)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            let results = try await provider.fetchBalances(context: makeSyncContext())
            #expect(results.count == 1)
            #expect(results[0].tokens[0].symbol == "ETH")
        }

        @Test
        func `parseJSONArray still handles raw top-level array`() async throws {
            let items: [[String: Any]] = [validTokenJSON(symbol: "DAI", name: "Dai")]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: items)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            let results = try await provider.fetchBalances(context: makeSyncContext())
            #expect(results.count == 1)
            #expect(results[0].tokens[0].symbol == "DAI")
        }
    }

    // MARK: Token Balance Parsing

    struct TokenBalanceTests {
        let session = makeMockSession()

        @Test
        func `partial missing fields — valid items parse, invalid dropped`() async throws {
            let items: [[String: Any]] = [
                validTokenJSON(symbol: "ETH"),
                ["name": "Missing Symbol", "balance": 1.0, "balanceUSD": 100.0] as [String: Any],
                ["symbol": "USDC"] as [String: Any],
                validTokenJSON(symbol: "DAI", name: "Dai", balance: 500.0, balanceUSD: 500.0)
            ]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: items)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            let results = try await provider.fetchBalances(context: makeSyncContext())
            #expect(results.count == 2)
            #expect(results[0].tokens[0].symbol == "ETH")
            #expect(results[1].tokens[0].symbol == "DAI")
        }

        @Test
        func `allItemsInvalid throws schemaChanged`() async throws {
            let items: [[String: Any]] = [
                ["name": "No Symbol"] as [String: Any],
                ["balance": 1.0] as [String: Any],
                ["random": "junk"] as [String: Any]
            ]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: items)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            do {
                _ = try await provider.fetchBalances(context: makeSyncContext())
                Issue.record("Expected ZapperError.schemaChanged but no error was thrown")
            } catch {
                guard case ZapperError.schemaChanged = error else {
                    Issue.record("Expected ZapperError.schemaChanged but got: \(error)")
                    return
                }
            }
        }
    }

    // MARK: App Position Parsing

    struct AppPositionTests {
        let session = makeMockSession()

        @Test
        func `partial missing appId — valid positions parse, invalid dropped`() async throws {
            let items: [[String: Any]] = [
                validAppPositionJSON(appId: "aave"),
                ["appName": "No ID", "type": "lending", "tokens": [] as [[String: Any]]] as [String: Any],
                validAppPositionJSON(appId: "compound", appName: "Compound")
            ]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: items)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            let results = try await provider.fetchDeFiPositions(context: makeSyncContext())
            #expect(results.count == 2)
            #expect(results[0].protocolId == "aave")
            #expect(results[1].protocolId == "compound")
        }

        @Test
        func `allMissingAppId throws schemaChanged`() async throws {
            let items: [[String: Any]] = [
                ["appName": "No ID 1", "type": "lending", "tokens": [] as [[String: Any]]] as [String: Any],
                ["appName": "No ID 2", "type": "staking", "tokens": [] as [[String: Any]]] as [String: Any]
            ]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: items)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            do {
                _ = try await provider.fetchDeFiPositions(context: makeSyncContext())
                Issue.record("Expected ZapperError.schemaChanged but no error was thrown")
            } catch {
                guard case ZapperError.schemaChanged = error else {
                    Issue.record("Expected ZapperError.schemaChanged but got: \(error)")
                    return
                }
            }
        }
    }

    // MARK: Position Token Parsing

    struct PositionTokenTests {
        let session = makeMockSession()

        @Test
        func `drops nested tokens with missing fields, valid ones parse`() async throws {
            let items: [[String: Any]] = [
                [
                    "appId": "aave",
                    "appName": "Aave",
                    "type": "lending",
                    "network": "ethereum",
                    "tokens": [
                        ["symbol": "ETH", "name": "Ethereum", "balance": 1.0, "balanceUSD": 2000.0, "type": "supply"] as [String: Any],
                        ["symbol": "USDC"] as [String: Any],
                        ["balance": 0.5, "balanceUSD": 1000.0] as [String: Any],
                        ["symbol": "DAI", "name": "Dai", "balance": 500.0, "balanceUSD": 500.0, "type": "supply"] as [String: Any]
                    ] as [[String: Any]]
                ] as [String: Any]
            ]
            ZapperMockURLProtocol.mockData = try JSONSerialization.data(withJSONObject: items)
            ZapperMockURLProtocol.mockStatusCode = 200

            let provider = makeProvider(session: session)
            let results = try await provider.fetchDeFiPositions(context: makeSyncContext())
            #expect(results.count == 1)
            #expect(results[0].tokens.count == 2)
            #expect(results[0].tokens[0].symbol == "ETH")
            #expect(results[0].tokens[1].symbol == "DAI")
        }
    }
}
