import Foundation
import Testing
import PortuCore
@testable import PortuNetwork

nonisolated
final class ZapperMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (Data?, Int))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (data, statusCode) = Self.requestHandler?(request) ?? (nil, 500)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

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
        ZapperMockURLProtocol.requestHandler = { _ in
            (json.data(using: .utf8), statusCode)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ZapperMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
