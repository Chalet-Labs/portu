import ComposableArchitecture
import Foundation
import PortuCore
import PortuNetwork

// MARK: - SyncEngineClient

struct SyncResult: Equatable {
    var failedAccounts: [String]
    var isPartial: Bool {
        !failedAccounts.isEmpty
    }
}

struct SyncEngineClient {
    var sync: @Sendable () async throws -> SyncResult
    var syncScope: @Sendable (PortfolioSyncScope) async throws -> SyncResult

    init(
        sync: @escaping @Sendable () async throws -> SyncResult,
        syncScope: @escaping @Sendable (PortfolioSyncScope) async throws -> SyncResult = { _ in SyncResult(failedAccounts: []) }) {
        self.sync = sync
        self.syncScope = syncScope
    }
}

extension SyncEngineClient: DependencyKey {
    static let liveValue = Self(
        sync: { fatalError("SyncEngineClient.liveValue must be overridden at Store creation") },
        syncScope: { _ in fatalError("SyncEngineClient.liveValue must be overridden at Store creation") })
    static let testValue = Self(
        sync: { SyncResult(failedAccounts: []) },
        syncScope: { _ in SyncResult(failedAccounts: []) })

    static func live(engine: SyncEngine) -> Self {
        Self(
            sync: { try await engine.sync() },
            syncScope: { scope in try await engine.sync(scope: scope) })
    }
}

extension DependencyValues {
    var syncEngine: SyncEngineClient {
        get { self[SyncEngineClient.self] }
        set { self[SyncEngineClient.self] = newValue }
    }
}

enum PortfolioSyncScope: Equatable {
    case zapper
    case exchange
}

// MARK: - PriceServiceClient

struct PriceServiceClient {
    enum ClientError: Error {
        /// Returned by `fetchZapperHistoricalPrices` when no Zapper API key is configured.
        /// The backfill runner's upstream pre-filter normally prevents reaching this path,
        /// but a missing key here means the candidate cannot be fetched — surface it as a
        /// failure instead of silently returning an empty result set.
        case zapperProviderUnavailable
    }

    var fetchPrices: @Sendable ([String]) async throws -> PriceUpdate
    private var fetchCoinGeckoPricesOverride: (@Sendable (PricePollingRequest) async throws -> PriceUpdate)?
    private var fetchZapperPricesOverride: (@Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate)?
    var fetchHistoricalPrices: @Sendable (String, Int) async throws -> [HistoricalPriceDTO]
    var resolveCoinGeckoIDs: @Sendable ([OnchainTokenIdentity]) async throws -> [OnchainTokenIdentity: String]
    var fetchZapperHistoricalPrices: @Sendable (OnchainTokenIdentity, Int) async throws -> [HistoricalPriceDTO]
    var canFetchZapperHistoricalPrices: @Sendable () -> Bool
    var invalidateCache: @Sendable () async -> Void

    var fetchCoinGeckoPrices: @Sendable (PricePollingRequest) async throws -> PriceUpdate {
        get {
            if let fetchCoinGeckoPricesOverride {
                return fetchCoinGeckoPricesOverride
            }
            let fetchPrices = fetchPrices
            return { request in
                try await fetchPrices(request.allPriceIDs)
            }
        }
        set { fetchCoinGeckoPricesOverride = newValue }
    }

    var fetchZapperPrices: @Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate {
        get {
            if let fetchZapperPricesOverride {
                return fetchZapperPricesOverride
            }
            let fetchPrices = fetchPrices
            return { identities in
                try await fetchPrices(identities.map(\.historicalPriceID))
            }
        }
        set { fetchZapperPricesOverride = newValue }
    }

    init(
        fetchPrices: @escaping @Sendable ([String]) async throws -> PriceUpdate,
        fetchCoinGeckoPrices: (@Sendable (PricePollingRequest) async throws -> PriceUpdate)? = nil,
        fetchZapperPrices: (@Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate)? = nil,
        fetchHistoricalPrices: @escaping @Sendable (String, Int) async throws -> [HistoricalPriceDTO],
        resolveCoinGeckoIDs: @escaping @Sendable ([OnchainTokenIdentity]) async throws -> [OnchainTokenIdentity: String] = { _ in [:] },
        fetchZapperHistoricalPrices: @escaping @Sendable (OnchainTokenIdentity, Int) async throws -> [HistoricalPriceDTO] = { _, _ in [] },
        canFetchZapperHistoricalPrices: @escaping @Sendable () -> Bool = { true },
        invalidateCache: @escaping @Sendable () async -> Void) {
        self.fetchPrices = fetchPrices
        self.fetchCoinGeckoPricesOverride = fetchCoinGeckoPrices
        self.fetchZapperPricesOverride = fetchZapperPrices
        self.fetchHistoricalPrices = fetchHistoricalPrices
        self.resolveCoinGeckoIDs = resolveCoinGeckoIDs
        self.fetchZapperHistoricalPrices = fetchZapperHistoricalPrices
        self.canFetchZapperHistoricalPrices = canFetchZapperHistoricalPrices
        self.invalidateCache = invalidateCache
    }
}

extension PriceServiceClient: DependencyKey {
    static let liveValue = Self(
        fetchPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchCoinGeckoPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchZapperPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchHistoricalPrices: { _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        resolveCoinGeckoIDs: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchZapperHistoricalPrices: { _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        canFetchZapperHistoricalPrices: { fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        invalidateCache: { fatalError("PriceServiceClient.liveValue must be overridden at Store creation") })
    static let testValue = Self(
        fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
        fetchHistoricalPrices: { _, _ in [] },
        resolveCoinGeckoIDs: { _ in [:] },
        fetchZapperHistoricalPrices: { _, _ in [] },
        canFetchZapperHistoricalPrices: { true },
        invalidateCache: {})

    static func live(service: PriceService, zapperProvider: ZapperProvider? = nil) -> Self {
        Self(
            fetchPrices: { coinIds in
                try await LivePriceUpdateBuilder.fetchPrices(
                    coinIds: coinIds,
                    priceService: service) { identities in
                        guard let zapperProvider, !identities.isEmpty else {
                            return PricePollingIDResolver.emptyUpdate
                        }
                        return try await zapperProvider.fetchPriceUpdate(for: identities)
                    }
            },
            fetchCoinGeckoPrices: { request in
                try await LivePriceUpdateBuilder.fetchCoinGeckoPrices(
                    request: request,
                    priceService: service)
            },
            fetchZapperPrices: { identities in
                guard let zapperProvider, !identities.isEmpty else {
                    return PricePollingIDResolver.emptyUpdate
                }
                return try await zapperProvider.fetchPriceUpdate(for: identities)
            },
            fetchHistoricalPrices: { coinId, days in
                try await service.fetchHistoricalPrices(for: coinId, days: days)
            },
            resolveCoinGeckoIDs: { identities in
                try await service.resolveCoinGeckoIDs(for: identities)
            },
            fetchZapperHistoricalPrices: { identity, days in
                guard let zapperProvider else {
                    throw ClientError.zapperProviderUnavailable
                }
                return try await zapperProvider.fetchHistoricalPrices(identity: identity, days: days)
            },
            canFetchZapperHistoricalPrices: { zapperProvider != nil },
            invalidateCache: { await service.invalidateCache() })
    }
}

extension DependencyValues {
    var priceService: PriceServiceClient {
        get { self[PriceServiceClient.self] }
        set { self[PriceServiceClient.self] = newValue }
    }
}

// MARK: - PricePollingSettingsClient

struct PricePollingSettingsClient {
    var refreshInterval: @Sendable () -> Duration
    var zapperFallbackInterval: @Sendable () -> Duration?
}

extension PricePollingSettingsClient: DependencyKey {
    static let liveValue = Self(
        refreshInterval: { PricePollingSettings.refreshInterval() },
        zapperFallbackInterval: { ProviderIntervalSettings.zapperLivePriceInterval() })
    static let testValue = Self(
        refreshInterval: { .seconds(PricePollingSettings.defaultRefreshIntervalSeconds) },
        zapperFallbackInterval: { .seconds(ProviderIntervalSettings.defaultZapperLivePriceIntervalSeconds) })
}

extension DependencyValues {
    var pricePollingSettings: PricePollingSettingsClient {
        get { self[PricePollingSettingsClient.self] }
        set { self[PricePollingSettingsClient.self] = newValue }
    }
}

// MARK: - ProviderSyncSettingsClient

struct ProviderSyncSettingsClient {
    var zapperPortfolioSyncInterval: @Sendable () -> Duration?
    var exchangePortfolioSyncInterval: @Sendable () -> Duration?
}

extension ProviderSyncSettingsClient: DependencyKey {
    static let liveValue = Self(
        zapperPortfolioSyncInterval: { ProviderIntervalSettings.zapperPortfolioSyncInterval() },
        exchangePortfolioSyncInterval: { ProviderIntervalSettings.exchangePortfolioSyncInterval() })
    static let testValue = Self(
        zapperPortfolioSyncInterval: { .seconds(ProviderIntervalSettings.defaultZapperPortfolioSyncIntervalSeconds) },
        exchangePortfolioSyncInterval: { .seconds(ProviderIntervalSettings.defaultExchangePortfolioSyncIntervalSeconds) })
}

extension DependencyValues {
    var providerSyncSettings: ProviderSyncSettingsClient {
        get { self[ProviderSyncSettingsClient.self] }
        set { self[ProviderSyncSettingsClient.self] = newValue }
    }
}

// MARK: - CurrentDateClient

struct CurrentDateClient {
    var now: @Sendable () -> Date
}

extension CurrentDateClient: DependencyKey {
    static let liveValue = Self(now: { Date.now })
    static let testValue = Self(now: { Date(timeIntervalSince1970: 1_000_000) })
}

extension DependencyValues {
    var currentDate: CurrentDateClient {
        get { self[CurrentDateClient.self] }
        set { self[CurrentDateClient.self] = newValue }
    }
}
