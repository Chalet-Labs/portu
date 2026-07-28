import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

extension ZerionProviderTests {
    @Test func `current prices preserve Solana mint case through response matching`() async throws {
        defer { ZerionMockURLProtocol.reset() }
        ZerionMockURLProtocol.respond { request in
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["filter[fungible_implementations]"] == "solana:SoLanaMiNtCase")
            return .init(data: Data(#"""
            {"data":[
              {"type":"fungibles","id":"solana-token","attributes":{
                "market_data":{"price":12.5,"changes":{"percent_1d":2}},
                "implementations":[{"chain_id":"solana","address":"SoLanaMiNtCase","decimals":9}]
              }}
            ],"links":{}}
            """#.utf8), statusCode: 200, headers: [:])
        }
        let provider = ZerionProvider(client: ZerionAPIClient(
            apiKey: { "test-key" },
            session: makeZerionMockSession(),
            minimumRequestInterval: .zero))
        let identity = OnchainTokenIdentity(chain: .solana, contractAddress: "SoLanaMiNtCase")

        let update = try await provider.fetchPriceUpdate(for: [identity])

        #expect(update.prices[identity.historicalPriceID] == Decimal(string: "12.5"))
        #expect(update.changes24h[identity.historicalPriceID] == Decimal(string: "0.02"))
    }
}
