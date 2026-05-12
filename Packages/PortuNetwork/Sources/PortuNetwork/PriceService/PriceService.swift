import Foundation
import PortuCore

/// Fetches and caches cryptocurrency prices from CoinGecko's free API.
/// Rate limit and cache TTL are configurable (see init).
public actor PriceService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!
    private var cache: [String: Decimal] = [:]
    private var lastFetchDate: Date?
    private var updateCache: PriceUpdate?
    private var lastUpdateFetchDate: Date?
    private let cacheTTL: TimeInterval
    private let coinGeckoAPIKey: @Sendable () async -> String?

    /// Sliding-window rate limiter
    private struct RequestStamp {
        let id: UUID
        let date: Date
    }

    private let maxRequestsPerWindow: Int
    private let windowDuration: TimeInterval
    private var requestTimestamps: [RequestStamp] = []
    private var activePollingTask: Task<Void, Never>?

    public init(
        session: URLSession = .shared,
        cacheTTL: TimeInterval = 10, // must be < polling interval to serve cached data between ticks
        maxRequestsPerWindow: Int = 10,
        windowDuration: TimeInterval = 60,
        coinGeckoAPIKey: @escaping @Sendable () async -> String? = { nil }) {
        self.session = session
        self.cacheTTL = cacheTTL
        self.maxRequestsPerWindow = maxRequestsPerWindow
        self.windowDuration = windowDuration
        self.coinGeckoAPIKey = coinGeckoAPIKey
    }

    /// Fetch current USD prices for the given CoinGecko coin IDs.
    /// Returns cached data if within TTL. Enforces client-side rate limit.
    public func fetchPrices(for coinIds: [String]) async throws(PriceServiceError) -> [String: Decimal] {
        guard !coinIds.isEmpty else { return [:] }

        if
            let lastFetch = lastFetchDate,
            Date.now.timeIntervalSince(lastFetch) < cacheTTL,
            coinIds.allSatisfy({ cache[$0] != nil }) {
            return cache.filter { coinIds.contains($0.key) }
        }

        let data = try await rateLimitedFetch(
            coinIds: coinIds,
            extraParams: [])

        let parsed = try CoinGeckoSimplePriceResponse(from: data)
        let requested = Set(coinIds)

        // Cap cache to prevent unbounded growth in long-running sessions
        if cache.count > 500 {
            cache = [:]
        }
        // Remove requested IDs not present in fresh payload to avoid serving stale values
        for id in requested where parsed.prices[id] == nil {
            cache.removeValue(forKey: id)
        }
        cache.merge(parsed.prices) { _, new in new }
        lastFetchDate = .now
        return cache.filter { requested.contains($0.key) }
    }

    /// Fetch current USD prices and 24h change percentages for the given CoinGecko coin IDs.
    /// Returns cached data if within TTL. Enforces client-side rate limit.
    public func fetchPriceUpdate(for coinIds: [String]) async throws(PriceServiceError) -> PriceUpdate {
        guard !coinIds.isEmpty else { return PriceUpdate(prices: [:], changes24h: [:]) }

        if
            let lastFetch = lastUpdateFetchDate,
            Date.now.timeIntervalSince(lastFetch) < cacheTTL,
            let cached = updateCache,
            coinIds.allSatisfy({ cached.prices[$0] != nil && cached.changes24h[$0] != nil }) {
            let requested = Set(coinIds)
            return PriceUpdate(
                prices: cached.prices.filter { requested.contains($0.key) },
                changes24h: cached.changes24h.filter { requested.contains($0.key) })
        }

        let data = try await rateLimitedFetch(
            coinIds: coinIds,
            extraParams: [URLQueryItem(name: "include_24hr_change", value: "true")])

        let parsed = try CoinGeckoSimplePriceResponse.parsePriceUpdate(from: data)
        updateCache = parsed
        lastUpdateFetchDate = .now
        let requested = Set(coinIds)
        return PriceUpdate(
            prices: parsed.prices.filter { requested.contains($0.key) },
            changes24h: parsed.changes24h.filter { requested.contains($0.key) })
    }

    public func fetchHistoricalPrices(
        for coinId: String,
        days: Int = 365) async throws(PriceServiceError) -> [HistoricalPriceDTO] {
        let normalized = coinId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        let data = try await rateLimitedFetch(
            pathComponents: ["coins", normalized, "market_chart"],
            queryItems: [
                URLQueryItem(name: "vs_currency", value: "usd"),
                URLQueryItem(name: "days", value: "\(max(days, 1))")
            ])
        return try CoinGeckoMarketChartResponse(coinGeckoId: normalized, data: data).prices
    }

    /// Shared rate limiting, stamping, network call, and HTTP status validation.
    private func rateLimitedFetch(
        coinIds: [String],
        extraParams: [URLQueryItem]) async throws(PriceServiceError) -> Data {
        let ids = Set(coinIds).joined(separator: ",")
        var params = [
            URLQueryItem(name: "ids", value: ids),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        params.append(contentsOf: extraParams)
        return try await rateLimitedFetch(pathComponents: ["simple", "price"], queryItems: params)
    }

    /// Shared rate limiting, stamping, network call, and HTTP status validation.
    private func rateLimitedFetch(
        pathComponents: [String],
        queryItems: [URLQueryItem]) async throws(PriceServiceError) -> Data {
        let now = Date.now
        requestTimestamps.removeAll { now.timeIntervalSince($0.date) > windowDuration }
        guard requestTimestamps.count < maxRequestsPerWindow else {
            throw .rateLimited
        }

        // Record timestamp before the await suspension point to prevent
        // interleaved calls from bypassing the rate limit
        let stamp = RequestStamp(id: UUID(), date: .now)
        requestTimestamps.append(stamp)

        var url = baseURL
        for component in pathComponents {
            url = url.appending(path: component)
        }
        url = url.appending(queryItems: queryItems)

        var request = URLRequest(url: url)
        if let key = await coinGeckoAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-cg-demo-api-key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            requestTimestamps.removeAll { $0.id == stamp.id }
            throw .networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw .invalidResponse(statusCode: 0)
        }
        switch http.statusCode {
        case 200: return data
        case 429: throw .rateLimited
        default: throw .invalidResponse(statusCode: http.statusCode)
        }
    }

    /// Returns an async stream that polls prices at the given interval.
    /// The stream yields price dictionaries keyed by coinGeckoId.
    /// Transient errors (network, rate limit) are silently retried on the next tick.
    /// Non-transient errors (decoding, invalid response) terminate the stream.
    ///
    /// - Important: Only one active stream per `PriceService` instance is supported.
    ///   Multiple concurrent streams share the same rate-limit budget and can silently
    ///   exhaust it, causing all streams to stop yielding values. Cancel the previous
    ///   stream before creating a new one.
    /// - Important: `coinIds` is captured at the point `priceStream` is called.
    ///   The stream will **not** automatically pick up coins added after creation.
    ///   Recreate the stream (e.g., via `.task(id: coinIdSet)`) whenever the active
    ///   set of tracked coins changes.
    public func priceStream(
        for coinIds: [String],
        interval: TimeInterval = 30) -> AsyncThrowingStream<[String: Decimal], any Error> {
        guard !coinIds.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }
        let pollingInterval = max(interval, 1)

        // Cancel any lingering polling task synchronously on the actor
        // before starting a new stream. This eliminates the race where
        // the old task's deferred cleanup hasn't executed yet.
        activePollingTask?.cancel()
        activePollingTask = nil

        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [String: Decimal].self,
            throwing: (any Error).self,
            bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            while !Task.isCancelled {
                do {
                    let prices = try await fetchPrices(for: coinIds)
                    continuation.yield(prices)
                } catch PriceServiceError.rateLimited {
                    // Transient — skip this tick, retry next
                } catch PriceServiceError.networkUnavailable {
                    // Transient — skip this tick, retry next
                } catch let PriceServiceError.invalidResponse(code) where code >= 500 {
                    // Transient server error — skip this tick, retry next
                } catch {
                    // Non-transient (decoding, 4xx auth errors) — terminate
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(pollingInterval))
                } catch {
                    // Cancellation — clean finish
                    continuation.finish()
                    return
                }
            }
            continuation.finish()
        }
        activePollingTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Clear the price cache, forcing a fresh fetch on next call.
    public func invalidateCache() {
        cache = [:]
        lastFetchDate = nil
        updateCache = nil
        lastUpdateFetchDate = nil
    }
}
