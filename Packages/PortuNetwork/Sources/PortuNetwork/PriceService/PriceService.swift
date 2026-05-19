import Foundation
import os
import PortuCore

/// Fetches and caches cryptocurrency prices from CoinGecko's free API.
/// Rate limit and cache TTL are configurable (see init).
public actor PriceService {
    private static let logger = Logger(subsystem: "com.portu.network", category: "PriceService")

    private let session: URLSession
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

    private enum Plan {
        case demo, pro
        var baseURL: URL {
            URL(string: self == .pro ? "https://pro-api.coingecko.com/api/v3" : "https://api.coingecko.com/api/v3")!
        }

        var authHeader: String {
            self == .pro ? "x-cg-pro-api-key" : "x-cg-demo-api-key"
        }
    }

    private var detectedPlan: Plan?
    private var detectedPlanKey: String?

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

    public func fetchTokenPriceUpdate(
        for identities: [OnchainTokenIdentity]) async throws(PriceServiceError) -> PriceUpdate {
        let uniqueIdentities = Self.uniqueIdentitiesPreservingOrder(identities)
        guard !uniqueIdentities.isEmpty else {
            return PriceUpdate(prices: [:], changes24h: [:])
        }

        var prices: [String: Decimal] = [:]
        var changes24h: [String: Decimal] = [:]
        let batches = Self.tokenPriceBatchesPreservingPriority(uniqueIdentities)
        for (index, batch) in batches.enumerated() {
            let result = try await fetchTokenPriceChunk(platformID: batch.platformID, identities: batch.identities)
            prices.merge(result.update.prices) { _, new in new }
            changes24h.merge(result.update.changes24h) { _, new in new }
            if result.didHitRateLimit {
                let remaining = batches[(index + 1)...].reduce(0) { $0 + $1.identities.count }
                if remaining > 0 {
                    let batchNumber = index + 1
                    Self.logger.warning(
                        """
                        Token price update truncated by rate limit after batch \
                        \(batchNumber, privacy: .public)/\(batches.count, privacy: .public); \
                        \(remaining, privacy: .public) identities skipped this tick.
                        """)
                }
                return PriceUpdate(prices: prices, changes24h: changes24h)
            }
        }

        return PriceUpdate(prices: prices, changes24h: changes24h)
    }

    public func resolveCoinGeckoIDs(
        for identities: [OnchainTokenIdentity]) async throws(PriceServiceError) -> [OnchainTokenIdentity: String] {
        let uniqueIdentities = Array(Set(identities)).sorted(by: Self.sortIdentities)
        guard !uniqueIdentities.isEmpty else { return [:] }

        let grouped = Dictionary(grouping: uniqueIdentities) { $0.chain }
        var resolved: [OnchainTokenIdentity: String] = [:]
        for chain in grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let networkID = chain.coinGeckoOnchainNetworkID else {
                continue
            }
            let identitiesForChain = grouped[chain, default: []]
            for chunk in identitiesForChain.chunked(size: 100) {
                let addresses = chunk.map(\.contractAddress).joined(separator: ",")
                let data = try await rateLimitedFetch(
                    pathComponents: ["onchain", "networks", networkID, "tokens", "multi", addresses],
                    queryItems: [])
                let parsed = try CoinGeckoOnchainTokenMapResponse(data: data)
                for identity in chunk {
                    if let coinGeckoID = parsed.coinGeckoIDsByAddress[identity.contractAddress] {
                        resolved[identity] = coinGeckoID
                    }
                }
            }
        }
        return resolved
    }

    private static func sortIdentities(
        _ lhs: OnchainTokenIdentity,
        _ rhs: OnchainTokenIdentity) -> Bool {
        if lhs.chain.rawValue != rhs.chain.rawValue { return lhs.chain.rawValue < rhs.chain.rawValue }
        return lhs.contractAddress < rhs.contractAddress
    }

    private static func uniqueIdentitiesPreservingOrder(
        _ identities: [OnchainTokenIdentity]) -> [OnchainTokenIdentity] {
        var seen: Set<OnchainTokenIdentity> = []
        var result: [OnchainTokenIdentity] = []
        for identity in identities where !seen.contains(identity) {
            seen.insert(identity)
            result.append(identity)
        }
        return result
    }

    private struct TokenPriceBatch {
        var platformID: String
        var identities: [OnchainTokenIdentity]
    }

    private static func tokenPriceBatchesPreservingPriority(
        _ identities: [OnchainTokenIdentity],
        chunkSize: Int = 100) -> [TokenPriceBatch] {
        var batches: [TokenPriceBatch] = []
        var currentChain: Chain?
        var currentIdentities: [OnchainTokenIdentity] = []

        func flushCurrentBatch() {
            guard
                let chain = currentChain,
                let platformID = chain.coinGeckoAssetPlatformID,
                !currentIdentities.isEmpty
            else {
                currentChain = nil
                currentIdentities.removeAll()
                return
            }

            for chunk in currentIdentities.chunked(size: chunkSize) {
                batches.append(TokenPriceBatch(platformID: platformID, identities: chunk))
            }
            currentChain = nil
            currentIdentities.removeAll()
        }

        for identity in identities {
            guard identity.chain.coinGeckoAssetPlatformID != nil else { continue }
            if currentChain == identity.chain {
                currentIdentities.append(identity)
            } else {
                flushCurrentBatch()
                currentChain = identity.chain
                currentIdentities = [identity]
            }
        }
        flushCurrentBatch()

        return batches
    }

    private struct TokenPriceFetchResult {
        var update: PriceUpdate
        var didHitRateLimit: Bool
    }

    private func fetchTokenPriceChunk(
        platformID: String,
        identities: [OnchainTokenIdentity]) async throws(PriceServiceError) -> TokenPriceFetchResult {
        let addresses = identities.map(\.contractAddress).joined(separator: ",")
        do {
            let data = try await rateLimitedFetch(
                pathComponents: ["simple", "token_price", platformID],
                queryItems: [
                    URLQueryItem(name: "contract_addresses", value: addresses),
                    URLQueryItem(name: "vs_currencies", value: "usd"),
                    URLQueryItem(name: "include_24hr_change", value: "true")
                ])
            return try TokenPriceFetchResult(
                update: tokenPriceUpdate(from: data, identities: identities),
                didHitRateLimit: false)
        } catch PriceServiceError.rateLimited {
            return TokenPriceFetchResult(
                update: PriceUpdate(prices: [:], changes24h: [:]),
                didHitRateLimit: true)
        } catch let PriceServiceError.invalidResponse(statusCode) where statusCode == 400 {
            guard identities.count > 1 else {
                // Single-identity 400 means CoinGecko rejected this specific contract.
                // Log so the user can spot it; the empty result keeps the rest of the run alive.
                if let lone = identities.first {
                    Self.logger.warning(
                        "CoinGecko returned 400 for token \(lone.historicalPriceID, privacy: .public); dropping for this tick.")
                }
                return TokenPriceFetchResult(
                    update: PriceUpdate(prices: [:], changes24h: [:]),
                    didHitRateLimit: false)
            }
            let midpoint = identities.count / 2
            let left = try await fetchTokenPriceChunk(
                platformID: platformID,
                identities: Array(identities[..<midpoint]))
            if left.didHitRateLimit { return left }
            let right = try await fetchTokenPriceChunk(
                platformID: platformID,
                identities: Array(identities[midpoint...]))
            return TokenPriceFetchResult(
                update: Self.merge(left.update, right.update),
                didHitRateLimit: right.didHitRateLimit)
        }
    }

    private func tokenPriceUpdate(
        from data: Data,
        identities: [OnchainTokenIdentity]) throws(PriceServiceError) -> PriceUpdate {
        let parsed = try CoinGeckoTokenPriceResponse(data: data)
        var prices: [String: Decimal] = [:]
        var changes24h: [String: Decimal] = [:]
        for identity in identities {
            let address = identity.contractAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let priceID = identity.historicalPriceID
            if let price = parsed.pricesByAddress[address] {
                prices[priceID] = price
            }
            if let change = parsed.changes24hByAddress[address] {
                changes24h[priceID] = change
            }
        }
        return PriceUpdate(prices: prices, changes24h: changes24h)
    }

    private static func merge(_ lhs: PriceUpdate, _ rhs: PriceUpdate) -> PriceUpdate {
        PriceUpdate(
            prices: lhs.prices.merging(rhs.prices) { _, new in new },
            changes24h: lhs.changes24h.merging(rhs.changes24h) { _, new in new })
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

        let trimmedKey = await coinGeckoAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmedKey?.isEmpty == false ? trimmedKey : nil
        let plan: Plan = if let key { await detectPlan(key: key) } else { .demo }

        var url = plan.baseURL
        for component in pathComponents {
            url = url.appending(component: component)
        }
        url = url.appending(queryItems: queryItems)

        var request = URLRequest(url: url)
        if let key {
            request.setValue(key, forHTTPHeaderField: plan.authHeader)
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

    private func detectPlan(key: String) async -> Plan {
        if let detectedPlan, detectedPlanKey == key { return detectedPlan }
        var probe = URLRequest(url: Plan.pro.baseURL.appending(component: "ping"))
        probe.setValue(key, forHTTPHeaderField: Plan.pro.authHeader)
        let plan: Plan
        do {
            let (_, response) = try await session.data(for: probe)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                plan = .pro
            } else {
                plan = .demo
            }
        } catch {
            plan = .demo
        }
        detectedPlan = plan
        detectedPlanKey = key
        return plan
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
                    // All three branches are transient (rate-limit, offline, upstream 5xx); skip
                    // the tick so the user keeps seeing the last good prices instead of an empty
                    // chart. Logged so a persistent outage is discoverable from Console.
                    Self.logger.notice("Price polling tick skipped: rate limited by CoinGecko.")
                } catch PriceServiceError.networkUnavailable {
                    Self.logger.notice("Price polling tick skipped: network unavailable.")
                } catch let PriceServiceError.invalidResponse(code) where code >= 500 {
                    Self.logger.notice("Price polling tick skipped: CoinGecko returned \(code, privacy: .public).")
                } catch {
                    // Non-transient (decoding, 4xx auth errors) — terminate the stream.
                    Self.logger.error(
                        "Price polling stream terminated: \(String(describing: error), privacy: .public)")
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

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            chunks.append(Array(self[index ..< nextIndex]))
            index = nextIndex
        }
        return chunks
    }
}
