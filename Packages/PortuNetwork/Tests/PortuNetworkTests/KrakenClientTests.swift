import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

@Suite(.serialized)
struct KrakenClientTests {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        self.session = URLSession(configuration: config)
    }

    // Regression test for Issue #10: non-empty Kraken `error` array must throw
    // `.apiError(messages:)`, not `.decodingFailed`.
    @Test func `kraken api error payload throws apiError not decodingFailed`() async {
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"error":["EAPI:Invalid key"],"result":{}}
            """.utf8), 200)
        }

        let client = KrakenClient(session: session)
        await #expect(throws: ExchangeError.apiError(messages: ["EAPI:Invalid key"])) {
            try await client.fetchBalances(apiKey: "test-key", apiSecret: "dGVzdA==", passphrase: nil)
        }
    }
}
