import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

/// Isolated URLProtocol for KrakenClient tests — separate static state from MockURLProtocol
/// used by PriceServiceTests to avoid inter-suite race conditions.
nonisolated final class KrakenMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (Data, Int))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (data, statusCode) = Self.requestHandler?(request) ?? (Data(), 500)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct KrakenClientTests {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KrakenMockURLProtocol.self]
        self.session = URLSession(configuration: config)
    }

    // Regression test for Issue #10: non-empty Kraken `error` array must throw
    // `.apiError(messages:)`, not `.decodingFailed`.
    @Test func `kraken api error payload throws apiError not decodingFailed`() async {
        KrakenMockURLProtocol.requestHandler = { _ in
            (Data(#"{"error":["EAPI:Invalid key"],"result":{}}"#.utf8), 200)
        }

        let client = KrakenClient(session: session)
        await #expect(throws: ExchangeError.apiError(messages: ["EAPI:Invalid key"])) {
            try await client.fetchBalances(apiKey: "test-key", apiSecret: "dGVzdA==", passphrase: nil)
        }
    }
}
