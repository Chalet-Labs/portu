import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

/// URLProtocol mock that returns responses via a per-test request handler.
/// Each test configures `requestHandler` before exercising PriceService,
/// keeping mock state explicit and co-located with each test case.
nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (Data?, Int))?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct PriceServiceTests {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        self.session = URLSession(configuration: config)
    }

    @Test func `fetch prices success`() async throws {
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":62400},"ethereum":{"usd":3200}}
            """.utf8), 200)
        }

        let service = PriceService(session: session)
        let prices = try await service.fetchPrices(for: ["bitcoin", "ethereum"])

        #expect(prices["bitcoin"] == 62400)
        #expect(prices["ethereum"] == 3200)
    }

    @Test func `fetch prices rate limited`() async {
        MockURLProtocol.requestHandler = { _ in (nil, 429) }

        let service = PriceService(session: session)
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }

    @Test func `cache returns cached data`() async throws {
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":62400}}
            """.utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch — hits network
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Change mock — but cache should still return old data
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":99999}}
            """.utf8), 200)
        }

        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 62400) // cached
    }

    @Test func `invalidate cache forces refetch`() async throws {
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":62400}}
            """.utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Update mock and invalidate cache
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":99999}}
            """.utf8), 200)
        }

        await service.invalidateCache()

        // Should fetch fresh data, not cached
        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 99999)
    }

    @Test func `fetch price update includes24h change`() async throws {
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":67500.0,"usd_24h_change":-1.5},"ethereum":{"usd":2188.0,"usd_24h_change":3.2}}
            """.utf8), 200)
        }

        let service = PriceService(session: session)
        let update = try await service.fetchPriceUpdate(for: ["bitcoin", "ethereum"])

        #expect(update.prices["bitcoin"] == Decimal(67500))
        #expect(update.prices["ethereum"] == Decimal(2188))
        #expect(try #require(update.changes24h["bitcoin"]) < 0)
        #expect(try #require(update.changes24h["ethereum"]) > 0)
    }

    @Test func `fetch historical prices builds market chart request and dedupes by utc day`() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (Data("""
            {
              "prices": [
                [1704067200000, 42000.25],
                [1704150000000, 43000.50],
                [1704153600000, 43100.75]
              ],
              "market_caps": [],
              "total_volumes": []
            }
            """.utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 0)
        let prices = try await service.fetchHistoricalPrices(for: " Bitcoin ", days: 365)

        #expect(capturedURL?.path == "/api/v3/coins/bitcoin/market_chart")
        let url = try #require(capturedURL)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "vs_currency", value: "usd")))
        #expect(query.contains(URLQueryItem(name: "days", value: "365")))
        #expect(prices.map(\.coinGeckoId) == ["bitcoin", "bitcoin"])
        let expectedPrices = try [
            #require(Decimal(string: "43000.50")),
            #require(Decimal(string: "43100.75"))
        ]
        #expect(prices.map(\.usdPrice) == expectedPrices)
    }

    @Test func `fetch historical prices escapes slash in coin id path component`() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (Data("{\"prices\":[]}".utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 0)
        _ = try await service.fetchHistoricalPrices(for: "foo/bar", days: 1)

        let url = try #require(capturedURL)
        #expect(url.absoluteString.contains("/coins/foo%2Fbar/market_chart?"))
        #expect(!url.absoluteString.contains("/coins/foo/bar/market_chart?"))
    }

    @Test func `fetch historical prices rejects malformed payload`() async {
        MockURLProtocol.requestHandler = { _ in
            (Data("{\"prices\":[[\"bad\", 42]]}".utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 0)
        await #expect(throws: PriceServiceError.decodingFailed) {
            try await service.fetchHistoricalPrices(for: "bitcoin", days: 365)
        }
    }

    @Test func `fetch historical prices maps http 429 to rate limited`() async {
        MockURLProtocol.requestHandler = { _ in (nil, 429) }

        let service = PriceService(session: session, cacheTTL: 0)
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchHistoricalPrices(for: "bitcoin", days: 365)
        }
    }

    @Test func `fetch historical prices sends demo api key header when provider returns a key`() async throws {
        var header: String?
        MockURLProtocol.requestHandler = { request in
            header = request.value(forHTTPHeaderField: "x-cg-demo-api-key")
            return (Data("{\"prices\":[]}".utf8), 200)
        }

        let service = PriceService(
            session: session,
            cacheTTL: 0,
            coinGeckoAPIKey: { "demo-key" })
        _ = try await service.fetchHistoricalPrices(for: "bitcoin", days: 365)

        #expect(header == "demo-key")
    }

    @Test func `rate limiter rejects excessive requests`() async throws {
        MockURLProtocol.requestHandler = { _ in
            (Data("""
            {"bitcoin":{"usd":62400}}
            """.utf8), 200)
        }

        // Create service with strict limit (3 requests per 60s) and no cache
        let service = PriceService(
            session: session,
            cacheTTL: 0,
            maxRequestsPerWindow: 3,
            windowDuration: 60)

        // First 3 requests succeed
        for _ in 0 ..< 3 {
            _ = try await service.fetchPrices(for: ["bitcoin"])
            await service.invalidateCache() // force re-fetch each time
        }

        // 4th request should be rate-limited
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }
}
