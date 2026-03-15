import Foundation
import PortuCore

/// Fetches and caches cryptocurrency prices from CoinGecko's free API.
/// Rate-limited to 10 requests/minute (sliding window). Cache TTL: 30 seconds.
public final class PriceService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!
    private var cache: [String: Decimal] = [:]
    private var lastFetchDate: Date?
    private let cacheTTL: TimeInterval

    // Sliding-window rate limiter: max 10 requests per 60 seconds
    private let maxRequestsPerWindow: Int
    private let windowDuration: TimeInterval
    private var requestTimestamps: [Date] = []

    public init(
        session: URLSession = .shared,
        cacheTTL: TimeInterval = 30,
        maxRequestsPerWindow: Int = 10,
        windowDuration: TimeInterval = 60
    ) {
        self.session = session
        self.cacheTTL = cacheTTL
        self.maxRequestsPerWindow = maxRequestsPerWindow
        self.windowDuration = windowDuration
    }

    /// Fetch current USD prices for the given CoinGecko coin IDs.
    /// Returns cached data if within TTL. Enforces client-side rate limit.
    public func fetchPrices(for coinIds: [String]) async throws(PriceServiceError) -> [String: Decimal] {
        if let lastFetch = lastFetchDate,
           Date.now.timeIntervalSince(lastFetch) < cacheTTL,
           coinIds.allSatisfy({ cache.keys.contains($0) }) {
            return cache
        }

        // Proactive rate limiting — reject before sending the request
        let now = Date.now
        requestTimestamps.removeAll { now.timeIntervalSince($0) > windowDuration }
        guard requestTimestamps.count < maxRequestsPerWindow else {
            throw .rateLimited
        }

        // Record timestamp before the await suspension point to prevent
        // interleaved calls from bypassing the rate limit
        requestTimestamps.append(.now)

        let ids = coinIds.joined(separator: ",")
        let url = baseURL.appending(path: "simple/price")
            .appending(queryItems: [
                URLQueryItem(name: "ids", value: ids),
                URLQueryItem(name: "vs_currencies", value: "usd"),
            ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw .networkUnavailable
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 429: throw .rateLimited
            default: throw .invalidResponse(statusCode: http.statusCode)
            }
        }

        let parsed = try CoinGeckoSimplePriceResponse(from: data)
        // Merge into cache so prices from prior requests for different coins are retained
        cache.merge(parsed.prices) { _, new in new }
        lastFetchDate = .now
        return cache
    }

    /// Returns an async stream that polls prices at the given interval.
    /// The stream yields price dictionaries keyed by coinGeckoId.
    /// Transient errors (network, rate limit) are silently retried on the next tick.
    /// Unexpected errors terminate the stream.
    public func priceStream(
        for coinIds: [String],
        interval: TimeInterval = 30
    ) -> AsyncThrowingStream<[String: Decimal], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        let prices = try await fetchPrices(for: coinIds)
                        continuation.yield(prices)
                    } catch is PriceServiceError {
                        // Transient errors (network, rate limit) — skip this tick, retry next
                    } catch {
                        // Unexpected error — terminate the stream
                        continuation.finish(throwing: error)
                        return
                    }
                    do {
                        try await Task.sleep(for: .seconds(interval))
                    } catch {
                        // Cancellation — clean finish
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Clear the price cache, forcing a fresh fetch on next call.
    public func invalidateCache() {
        cache = [:]
        lastFetchDate = nil
    }
}
