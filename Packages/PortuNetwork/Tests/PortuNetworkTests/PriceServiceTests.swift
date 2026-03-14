import Testing
import Foundation
@testable import PortuNetwork

/// URLProtocol mock that returns a pre-configured response.
nonisolated
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = Self.mockData {
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
        let json = """
        {"bitcoin":{"usd":62400},"ethereum":{"usd":3200}}
        """
        MockURLProtocol.mockData = json.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = PriceService(session: session)
        let prices = try await service.fetchPrices(for: ["bitcoin", "ethereum"])

        #expect(prices["bitcoin"] == 62400)
        #expect(prices["ethereum"] == 3200)
    }

    @Test func fetchPricesRateLimited() async {
        MockURLProtocol.mockData = nil
        MockURLProtocol.mockStatusCode = 429

        let service = PriceService(session: session)
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }

    @Test func cacheReturnsCachedData() async throws {
        let json = """
        {"bitcoin":{"usd":62400}}
        """
        MockURLProtocol.mockData = json.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch — hits network
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Change mock — but cache should still return old data
        MockURLProtocol.mockData = """
        {"bitcoin":{"usd":99999}}
        """.data(using: .utf8)

        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 62400) // cached
    }

    @Test func invalidateCacheForcesRefetch() async throws {
        let json = """
        {"bitcoin":{"usd":62400}}
        """
        MockURLProtocol.mockData = json.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Update mock and invalidate cache
        MockURLProtocol.mockData = """
        {"bitcoin":{"usd":99999}}
        """.data(using: .utf8)

        service.invalidateCache()

        // Should fetch fresh data, not cached
        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 99999)
    }

    @Test func rateLimiterRejectsExcessiveRequests() async throws {
        let json = """
        {"bitcoin":{"usd":62400}}
        """
        MockURLProtocol.mockData = json.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

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
            service.invalidateCache() // force re-fetch each time
        }

        // 4th request should be rate-limited
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }
}
