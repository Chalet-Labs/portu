import Foundation
import PortuCore

public struct PriceUpdate: Sendable, Equatable {
    public let prices: [String: Decimal]
    public let changes24h: [String: Decimal]

    public init(prices: [String: Decimal], changes24h: [String: Decimal]) {
        self.prices = prices
        self.changes24h = changes24h
    }
}

/// Fetches and caches cryptocurrency prices from CoinGecko's free API.
/// Rate limit and cache TTL are configurable (see init).
public actor PriceService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!
    private var priceCache: [String: Decimal] = [:]
    private var changeCache: [String: Decimal] = [:]
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
    private var activePollingTask: Task<Void, Never>?

    public init(
        session: URLSession = .shared,
        cacheTTL: TimeInterval = 10, // must be < polling interval to serve cached data between ticks
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
        try await fetchPriceUpdate(for: coinIds).prices
    }

    public func fetchHistoricalPrices(
        for coinId: String,
        days: Int
    ) async throws(PriceServiceError) -> [HistoricalPricePoint] {
        let trimmedCoinID = coinId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCoinID.isEmpty, days > 0 else {
            throw .invalidRequest
        }

        let stamp = try recordRequestAttempt()
        let url = baseURL
            .appending(path: "coins")
            .appending(path: trimmedCoinID)
            .appending(path: "market_chart")
            .appending(queryItems: [
                URLQueryItem(name: "vs_currency", value: "usd"),
                URLQueryItem(name: "days", value: String(days)),
                URLQueryItem(name: "interval", value: "daily"),
            ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            rollbackRequestAttempt(stamp)
            throw .networkUnavailable
        }

        try validate(response: response)
        return try CoinGeckoMarketChartResponse(from: data).prices
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
        interval: TimeInterval = 30
    ) -> AsyncThrowingStream<PriceUpdate, any Error> {
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
            of: PriceUpdate.self,
            throwing: (any Error).self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let task = Task {
            while !Task.isCancelled {
                do {
                    let update = try await fetchPriceUpdate(for: coinIds)
                    continuation.yield(update)
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
        priceCache = [:]
        changeCache = [:]
        lastFetchDate = nil
    }

    private func fetchPriceUpdate(for coinIds: [String]) async throws(PriceServiceError) -> PriceUpdate {
        guard !coinIds.isEmpty else {
            return PriceUpdate(prices: [:], changes24h: [:])
        }

        let requestedIDs = Array(Set(coinIds)).sorted()
        if let cachedUpdate = cachedUpdate(for: requestedIDs) {
            return cachedUpdate
        }

        let stamp = try recordRequestAttempt()
        let url = baseURL
            .appending(path: "simple/price")
            .appending(queryItems: [
                URLQueryItem(name: "ids", value: requestedIDs.joined(separator: ",")),
                URLQueryItem(name: "vs_currencies", value: "usd"),
                URLQueryItem(name: "include_24hr_change", value: "true"),
            ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            rollbackRequestAttempt(stamp)
            throw .networkUnavailable
        }

        try validate(response: response)

        let parsed = try CoinGeckoSimplePriceResponse(from: data)
        let requestedSet = Set(requestedIDs)

        if priceCache.count > 500 || changeCache.count > 500 {
            priceCache = [:]
            changeCache = [:]
        }

        for id in requestedSet where parsed.prices[id] == nil {
            priceCache.removeValue(forKey: id)
            changeCache.removeValue(forKey: id)
        }

        priceCache.merge(parsed.prices) { _, new in new }
        changeCache.merge(parsed.changes24h) { _, new in new }
        lastFetchDate = .now

        return PriceUpdate(
            prices: priceCache.filter { requestedSet.contains($0.key) },
            changes24h: changeCache.filter { requestedSet.contains($0.key) }
        )
    }

    private func cachedUpdate(for coinIds: [String]) -> PriceUpdate? {
        guard let lastFetchDate,
              Date.now.timeIntervalSince(lastFetchDate) < cacheTTL,
              coinIds.allSatisfy({ priceCache[$0] != nil })
        else {
            return nil
        }

        let requestedSet = Set(coinIds)
        return PriceUpdate(
            prices: priceCache.filter { requestedSet.contains($0.key) },
            changes24h: changeCache.filter { requestedSet.contains($0.key) }
        )
    }

    private func recordRequestAttempt() throws(PriceServiceError) -> RequestStamp {
        let now = Date.now
        requestTimestamps.removeAll { now.timeIntervalSince($0.date) > windowDuration }
        guard requestTimestamps.count < maxRequestsPerWindow else {
            throw .rateLimited
        }

        let stamp = RequestStamp(id: UUID(), date: now)
        requestTimestamps.append(stamp)
        return stamp
    }

    private func rollbackRequestAttempt(_ stamp: RequestStamp) {
        requestTimestamps.removeAll { $0.id == stamp.id }
    }

    private func validate(response: URLResponse) throws(PriceServiceError) {
        guard let http = response as? HTTPURLResponse else {
            throw .invalidResponse(statusCode: 0)
        }

        switch http.statusCode {
        case 200:
            return
        case 429:
            throw .rateLimited
        default:
            throw .invalidResponse(statusCode: http.statusCode)
        }
    }
}
