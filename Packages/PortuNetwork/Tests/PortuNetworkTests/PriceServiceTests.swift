import Testing
import Foundation
@testable import PortuNetwork

/// URLProtocol mock that returns responses via a per-test request handler.
/// Each test configures `requestHandler` before exercising PriceService,
/// keeping mock state explicit and co-located with each test case.
nonisolated
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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

@Suite("PriceService Tests", .serialized)
struct PriceServiceTests {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    @Test func fetchPricesSuccess() async throws {
        MockURLProtocol.requestHandler = { _ in
            ("""
            {
              "bitcoin":{"usd":62400,"usd_24h_change":4.5},
              "ethereum":{"usd":3200,"usd_24h_change":2.1}
            }
            """.data(using: .utf8), 200)
        }

        let service = PriceService(session: session)
        let prices = try await service.fetchPrices(for: ["bitcoin", "ethereum"])

        #expect(prices["bitcoin"] == 62400)
        #expect(prices["ethereum"] == 3200)
    }

    @Test func fetchPricesRateLimited() async {
        MockURLProtocol.requestHandler = { _ in (nil, 429) }

        let service = PriceService(session: session)
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }

    @Test func cacheReturnsCachedData() async throws {
        MockURLProtocol.requestHandler = { _ in
            ("""
            {"bitcoin":{"usd":62400}}
            """.data(using: .utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch — hits network
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Change mock — but cache should still return old data
        MockURLProtocol.requestHandler = { _ in
            ("""
            {"bitcoin":{"usd":99999}}
            """.data(using: .utf8), 200)
        }

        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 62400) // cached
    }

    @Test func invalidateCacheForcesRefetch() async throws {
        MockURLProtocol.requestHandler = { _ in
            ("""
            {"bitcoin":{"usd":62400}}
            """.data(using: .utf8), 200)
        }

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Update mock and invalidate cache
        MockURLProtocol.requestHandler = { _ in
            ("""
            {"bitcoin":{"usd":99999}}
            """.data(using: .utf8), 200)
        }

        await service.invalidateCache()

        // Should fetch fresh data, not cached
        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 99999)
    }

    @Test func rateLimiterRejectsExcessiveRequests() async throws {
        MockURLProtocol.requestHandler = { _ in
            ("""
            {"bitcoin":{"usd":62400,"usd_24h_change":4.5}}
            """.data(using: .utf8), 200)
        }

        // Create service with strict limit (3 requests per 60s) and no cache
        let service = PriceService(
            session: session,
            cacheTTL: 0,
            maxRequestsPerWindow: 3,
            windowDuration: 60
        )

        // First 3 requests succeed
        for _ in 0..<3 {
            _ = try await service.fetchPrices(for: ["bitcoin"])
            await service.invalidateCache() // force re-fetch each time
        }

        // 4th request should be rate-limited
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }

    @Test func priceStreamYieldsPriceUpdatePayloads() async throws {
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path() {
            case "/api/v3/simple/price":
                return ("""
                {"bitcoin":{"usd":62400,"usd_24h_change":4.5}}
                """.data(using: .utf8), 200)
            default:
                return (nil, 404)
            }
        }

        let service = PriceService(session: session, cacheTTL: 0)
        let stream = await service.priceStream(for: ["bitcoin"], interval: 1)
        var iterator = stream.makeAsyncIterator()
        let update = try #require(try await iterator.next())

        #expect(update.prices["bitcoin"] == 62400)
        #expect(update.changes24h["bitcoin"] == 4.5)
    }

    @Test func historicalPricesDecodeChronologicalSeries() async throws {
        let entries = (0..<30).map { dayOffset in
            let timestamp = 1_700_000_000_000 + (dayOffset * 86_400_000)
            let price = 62_400 + dayOffset
            return "[\(timestamp),\(price)]"
        }
        let historyJSON = """
        {"prices":[\(entries.joined(separator: ","))]}
        """

        MockURLProtocol.requestHandler = { request in
            switch request.url?.path() {
            case "/api/v3/coins/bitcoin/market_chart":
                return (historyJSON.data(using: .utf8), 200)
            default:
                return (nil, 404)
            }
        }

        let service = PriceService(session: session, cacheTTL: 0)
        let series = try await service.fetchHistoricalPrices(for: "bitcoin", days: 30)

        #expect(series.count == 30)
        #expect(series.first?.price == 62400)
        #expect(series.last?.price == 62429)
    }
}
