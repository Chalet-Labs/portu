import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

@Suite(.serialized)
struct ZapperProviderPartialResponseTests {
    let session = makeMockSession()

    init() {
        ZapperMockURLProtocol.reset()
    }

    @Test
    func `fetchBalances skips null partial edges and nodes`() async throws {
        defer { ZapperMockURLProtocol.reset() }
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(tokenResponse(edges: [
                NSNull(),
                ["node": NSNull()],
                tokenBalanceEdge(symbol: "ETH"),
                tokenBalanceEdge(symbol: "DAI", tokenAddress: "0xdai")
            ])), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchBalances(context: makeSyncContext())

        #expect(results.map { $0.tokens[0].symbol } == ["ETH", "DAI"])
    }

    @Test
    func `fetchDeFiPositions skips null partial app edges position edges and tokens`() async throws {
        let validContractEdge = contractPositionEdge(tokens: [
            NSNull(),
            ["metaType": "SUPPLIED", "token": NSNull()],
            tokenWithMetaType("SUPPLIED", address: "0xeth", balance: "1.0", balanceUSD: 2000.0, symbol: "ETH")
        ])
        defer { ZapperMockURLProtocol.reset() }
        ZapperMockURLProtocol.requestHandler = { _ in
            try (jsonData(appBalancesResponse(appEdges: [
                NSNull(),
                ["node": NSNull()],
                appBalanceEdge(positionEdges: [
                    NSNull(),
                    ["node": NSNull()],
                    validContractEdge,
                    appTokenPositionEdge()
                ])
            ])), 200)
        }

        let provider = makeProvider(session: session)
        let results = try await provider.fetchDeFiPositions(context: makeSyncContext())

        #expect(results.count == 2)
        #expect(results.flatMap(\.tokens).map(\.symbol) == ["ETH", "aEthUSDC"])
    }
}
