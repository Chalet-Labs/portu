import Foundation
import PortuCore

/// Fetches and caches cryptocurrency prices from CoinGecko's free API.
/// Rate limit and cache TTL are configurable (see init).
public actor PriceService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!
    private var cache: [String: Decimal] = [:]
    private var lastFetchDate: Date?
    private let cacheTTL: TimeInterval

    // Sliding-window rate limiter
    private struct RequestStamp: Sendable {
        let id: UUID
        let date: Date
    }
    private let maxRequestsPerWindow: Int
    private let windowDuration: TimeInterval
    private var requestTimestamps: [RequestStamp] = []

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
        guard !coinIds.isEmpty else { return [:] }

        if let lastFetch = lastFetchDate,
           Date.now.timeIntervalSince(lastFetch) < cacheTTL,
           coinIds.allSatisfy({ cache.keys.contains($0) }) {
            return cache.filter { coinIds.contains($0.key) }
        }

        // Proactive rate limiting — reject before sending the request
        let now = Date.now
        requestTimestamps.removeAll { now.timeIntervalSince($0.date) > windowDuration }
        guard requestTimestamps.count < maxRequestsPerWindow else {
            throw .rateLimited
        }

        // Record timestamp before the await suspension point to prevent
        // interleaved calls from bypassing the rate limit
        let stamp = RequestStamp(id: UUID(), date: .now)
        requestTimestamps.append(stamp)

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
            requestTimestamps.removeAll { $0.id == stamp.id }
            throw .networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw .invalidResponse(statusCode: 0)
        }
        switch http.statusCode {
        case 200: break
        case 429: throw .rateLimited
        default: throw .invalidResponse(statusCode: http.statusCode)
        }

        let parsed = try CoinGeckoSimplePriceResponse(from: data)
        // Cap cache to prevent unbounded growth in long-running sessions
        if cache.count > 500 {
            cache = [:]
        }
        cache.merge(parsed.prices) { _, new in new }
        lastFetchDate = .now
        return cache.filter { coinIds.contains($0.key) }
    }

    /// Returns an async stream that polls prices at the given interval.
    /// The stream yields price dictionaries keyed by coinGeckoId.
    /// Transient errors (network, rate limit) are silently retried on the next tick.
    /// Non-transient errors (decoding, invalid response) terminate the stream.
    public func priceStream(
        for coinIds: [String],
        interval: TimeInterval = 30
    ) -> AsyncThrowingStream<[String: Decimal], any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [String: Decimal].self,
            throwing: (any Error).self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let task = Task {
            while !Task.isCancelled {
                do {
                    let prices = try await fetchPrices(for: coinIds)
                    continuation.yield(prices)
                } catch PriceServiceError.rateLimited {
                    // Transient — skip this tick, retry next
                } catch PriceServiceError.networkUnavailable {
                    // Transient — skip this tick, retry next
                } catch PriceServiceError.invalidResponse(let code) where code >= 500 {
                    // Transient server error — skip this tick, retry next
                } catch {
                    // Non-transient (decoding, 4xx auth errors) — terminate
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
        return stream
    }

    /// Clear the price cache, forcing a fresh fetch on next call.
    public func invalidateCache() {
        cache = [:]
        lastFetchDate = nil
    }
}
