import Foundation
import Testing
import PortuCore
@testable import PortuNetwork

@Suite("Zapper Provider Tests", .serialized)
struct ZapperProviderTests {
    @Test func zapperProviderMapsBalancesIntoPositionDTOs() async throws {
        let fixture = """
        {
          "positions": [
            {
              "positionType": "idle",
              "chain": "ethereum",
              "protocolId": null,
              "protocolName": "Wallet",
              "protocolLogoURL": null,
              "healthFactor": null,
              "tokens": [
                {
                  "role": "balance",
                  "symbol": "ETH",
                  "name": "Ethereum",
                  "amount": 1.0,
                  "usdValue": 3200,
                  "chain": "ethereum",
                  "contractAddress": null,
                  "debankId": null,
                  "coinGeckoId": "ethereum",
                  "sourceKey": "zapper:eth",
                  "logoURL": null,
                  "category": "major",
                  "isVerified": true
                }
              ]
            }
          ]
        }
        """
        let provider = ZapperProvider(session: mockedSession(json: fixture))
        let context = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [(address: "0xabc", chain: nil)],
            exchangeType: nil
        )

        let balances = try await provider.fetchBalances(context: context)

        #expect(balances.count == 1)
        #expect(balances[0].tokens[0].coinGeckoId == "ethereum")
    }

    private func mockedSession(json: String, statusCode: Int = 200) -> URLSession {
        MockURLProtocol.requestHandler = { _ in
            (json.data(using: .utf8), statusCode)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
