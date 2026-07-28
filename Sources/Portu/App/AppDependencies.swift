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
    var syncAccount: @Sendable (UUID) async throws -> SyncResult

    init(
        sync: @escaping @Sendable () async throws -> SyncResult,
        syncScope: @escaping @Sendable (PortfolioSyncScope) async throws -> SyncResult = { _ in SyncResult(failedAccounts: []) },
        syncAccount: @escaping @Sendable (UUID) async throws -> SyncResult = { _ in SyncResult(failedAccounts: []) }) {
        self.sync = sync
        self.syncScope = syncScope
        self.syncAccount = syncAccount
    }
}

extension SyncEngineClient: DependencyKey {
    static let liveValue = Self(
        sync: { fatalError("SyncEngineClient.liveValue must be overridden at Store creation") },
        syncScope: { _ in fatalError("SyncEngineClient.liveValue must be overridden at Store creation") },
        syncAccount: { _ in fatalError("SyncEngineClient.liveValue must be overridden at Store creation") })
    static let testValue = Self(
        sync: { SyncResult(failedAccounts: []) },
        syncScope: { _ in SyncResult(failedAccounts: []) },
        syncAccount: { _ in SyncResult(failedAccounts: []) })

    static func live(engine: SyncEngine) -> Self {
        Self(
            sync: { try await engine.sync() },
            syncScope: { scope in try await engine.sync(scope: scope) },
            syncAccount: { accountID in try await engine.sync(accountID: accountID) })
    }
}

extension DependencyValues {
    var syncEngine: SyncEngineClient {
        get { self[SyncEngineClient.self] }
        set { self[SyncEngineClient.self] = newValue }
    }
}

enum PortfolioSyncScope: Equatable {
    case onchain
    case exchange
}

// MARK: - PriceServiceClient

struct PriceServiceClient {
    enum ClientError: Error {
        /// Returned by `fetchOnchainHistoricalPrices` when no Zerion API key is configured.
        /// The backfill runner's upstream pre-filter normally prevents reaching this path,
        /// but a missing key here means the candidate cannot be fetched — surface it as a
        /// failure instead of silently returning an empty result set.
        case onchainProviderUnavailable
    }

    var fetchPrices: @Sendable ([String]) async throws -> PriceUpdate
    private var fetchCoinGeckoPricesOverride: (@Sendable (PricePollingRequest, FiatCurrency, Decimal) async throws -> PriceUpdate)?
    private var fetchOnchainFallbackPricesOverride: (@Sendable ([OnchainTokenIdentity], FiatCurrency, Decimal) async throws -> PriceUpdate)?
    var fetchHistoricalPrices: @Sendable (String, Int) async throws -> [HistoricalPriceDTO]
    var fetchHistoricalPricesForCurrency: @Sendable (String, FiatCurrency, Int) async throws -> [HistoricalPriceDTO]
    var fetchCurrentUSDConversionRate: @Sendable (FiatCurrency) async throws -> Decimal
    var fetchHistoricalUSDConversionRates: @Sendable (FiatCurrency, Int) async throws -> [CurrencyConversionRate]
    var resolveCoinGeckoIDs: @Sendable ([OnchainTokenIdentity]) async throws -> [OnchainTokenIdentity: String]
    var fetchOnchainHistoricalPrices: @Sendable (OnchainTokenIdentity, Int) async throws -> [HistoricalPriceDTO]
    var canFetchOnchainHistoricalPrices: @Sendable () async throws -> Bool
    var invalidateCache: @Sendable () async -> Void

    var fetchCoinGeckoPrices: @Sendable (PricePollingRequest, FiatCurrency, Decimal) async throws -> PriceUpdate {
        get {
            if let fetchCoinGeckoPricesOverride {
                return fetchCoinGeckoPricesOverride
            }
            let fetchPrices = fetchPrices
            return { request, currency, _ in
                // The default fetcher only knows how to return USD-tagged updates. A non-USD
                // request would be discarded by the reducer's currency guard and stall polling,
                // so return an empty update tagged with the requested currency instead.
                guard currency == .default else {
                    return PricePollingIDResolver.emptyUpdate(currency: currency)
                }
                return try await fetchPrices(request.allPriceIDs)
            }
        }
        set { fetchCoinGeckoPricesOverride = newValue }
    }

    var fetchOnchainFallbackPrices: @Sendable ([OnchainTokenIdentity], FiatCurrency, Decimal) async throws -> PriceUpdate {
        get {
            if let fetchOnchainFallbackPricesOverride {
                return fetchOnchainFallbackPricesOverride
            }
            let fetchPrices = fetchPrices
            return { identities, currency, _ in
                // See fetchCoinGeckoPrices: the default fetcher is USD-only, so a non-USD
                // request returns an empty update tagged with the requested currency rather
                // than a USD update the reducer would discard.
                guard currency == .default else {
                    return PricePollingIDResolver.emptyUpdate(currency: currency)
                }
                return try await fetchPrices(identities.map(\.historicalPriceID))
            }
        }
        set { fetchOnchainFallbackPricesOverride = newValue }
    }

    init(
        fetchPrices: @escaping @Sendable ([String]) async throws -> PriceUpdate,
        fetchCoinGeckoPrices: (@Sendable (PricePollingRequest, FiatCurrency, Decimal) async throws -> PriceUpdate)? = nil,
        fetchOnchainFallbackPrices: (@Sendable ([OnchainTokenIdentity], FiatCurrency, Decimal) async throws -> PriceUpdate)? = nil,
        fetchHistoricalPrices: @escaping @Sendable (String, Int) async throws -> [HistoricalPriceDTO],
        fetchHistoricalPricesForCurrency: (@Sendable (String, FiatCurrency, Int) async throws -> [HistoricalPriceDTO])? = nil,
        fetchCurrentUSDConversionRate: @escaping @Sendable (FiatCurrency) async throws -> Decimal = { _ in 1 },
        fetchHistoricalUSDConversionRates: @escaping @Sendable (FiatCurrency, Int) async throws -> [CurrencyConversionRate] = { _, _ in [] },
        resolveCoinGeckoIDs: @escaping @Sendable ([OnchainTokenIdentity]) async throws -> [OnchainTokenIdentity: String] = { _ in [:] },
        fetchOnchainHistoricalPrices: @escaping @Sendable (OnchainTokenIdentity, Int) async throws -> [HistoricalPriceDTO] = { _, _ in [] },
        canFetchOnchainHistoricalPrices: @escaping @Sendable () async throws -> Bool = { true },
        invalidateCache: @escaping @Sendable () async -> Void) {
        self.fetchPrices = fetchPrices
        self.fetchCoinGeckoPricesOverride = fetchCoinGeckoPrices
        self.fetchOnchainFallbackPricesOverride = fetchOnchainFallbackPrices
        self.fetchHistoricalPrices = fetchHistoricalPrices
        self.fetchHistoricalPricesForCurrency = fetchHistoricalPricesForCurrency ?? { coinId, currency, days in
            guard currency == .default else { return [] }
            return try await fetchHistoricalPrices(coinId, days)
        }
        self.fetchCurrentUSDConversionRate = fetchCurrentUSDConversionRate
        self.fetchHistoricalUSDConversionRates = fetchHistoricalUSDConversionRates
        self.resolveCoinGeckoIDs = resolveCoinGeckoIDs
        self.fetchOnchainHistoricalPrices = fetchOnchainHistoricalPrices
        self.canFetchOnchainHistoricalPrices = canFetchOnchainHistoricalPrices
        self.invalidateCache = invalidateCache
    }
}

extension PriceServiceClient: DependencyKey {
    static let liveValue = Self(
        fetchPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchCoinGeckoPrices: { _, _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchOnchainFallbackPrices: { _, _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchHistoricalPrices: { _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchHistoricalPricesForCurrency: { _, _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchCurrentUSDConversionRate: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchHistoricalUSDConversionRates: { _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        resolveCoinGeckoIDs: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchOnchainHistoricalPrices: { _, _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        canFetchOnchainHistoricalPrices: { fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        invalidateCache: { fatalError("PriceServiceClient.liveValue must be overridden at Store creation") })
    static let testValue = Self(
        fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
        fetchHistoricalPrices: { _, _ in [] },
        resolveCoinGeckoIDs: { _ in [:] },
        fetchOnchainHistoricalPrices: { _, _ in [] },
        canFetchOnchainHistoricalPrices: { true },
        invalidateCache: {})

    static func live(service: PriceService, zerionProvider: ZerionProvider? = nil) -> Self {
        Self(
            fetchPrices: { coinIds in
                try await LivePriceUpdateBuilder.fetchPrices(
                    coinIds: coinIds,
                    priceService: service) { identities in
                        guard let zerionProvider, !identities.isEmpty else {
                            return PricePollingIDResolver.emptyUpdate
                        }
                        return try await zerionProvider.fetchPriceUpdate(for: identities)
                    }
            },
            fetchCoinGeckoPrices: { request, currency, usdToDisplayRate in
                let update = try await LivePriceUpdateBuilder.fetchCoinGeckoPrices(
                    request: request,
                    priceService: service,
                    currency: .usd)
                guard currency != .usd else { return update }
                return update.convertedUSDValues(to: currency, rate: usdToDisplayRate, preserveChanges24h: true)
            },
            fetchOnchainFallbackPrices: { identities, currency, usdToDisplayRate in
                guard let zerionProvider, !identities.isEmpty else {
                    return PricePollingIDResolver.emptyUpdate(currency: currency)
                }
                let update = try await zerionProvider.fetchPriceUpdate(for: identities)
                guard currency != .usd else { return update }
                return update.convertedUSDValues(
                    to: currency,
                    rate: usdToDisplayRate,
                    preserveChanges24h: true)
            },
            fetchHistoricalPrices: { coinId, days in
                try await service.fetchHistoricalPrices(for: coinId, days: days)
            },
            fetchHistoricalPricesForCurrency: { coinId, currency, days in
                try await service.fetchHistoricalPrices(for: coinId, currency: currency, days: days)
            },
            fetchCurrentUSDConversionRate: { currency in
                try await service.fetchCurrentUSDConversionRate(to: currency)
            },
            fetchHistoricalUSDConversionRates: { currency, days in
                try await service.fetchHistoricalUSDConversionRates(to: currency, days: days)
            },
            resolveCoinGeckoIDs: { identities in
                try await service.resolveCoinGeckoIDs(for: identities)
            },
            fetchOnchainHistoricalPrices: { identity, days in
                guard let zerionProvider else {
                    throw ClientError.onchainProviderUnavailable
                }
                return try await zerionProvider.fetchHistoricalPrices(identity: identity, days: days)
            },
            canFetchOnchainHistoricalPrices: { zerionProvider != nil },
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
    var onchainFallbackInterval: @Sendable () -> Duration?
}

extension PricePollingSettingsClient: DependencyKey {
    static let liveValue = Self(
        refreshInterval: { PricePollingSettings.refreshInterval() },
        onchainFallbackInterval: { ProviderIntervalSettings.onchainLivePriceInterval() })
    static let testValue = Self(
        refreshInterval: { .seconds(PricePollingSettings.defaultRefreshIntervalSeconds) },
        onchainFallbackInterval: { .seconds(ProviderIntervalSettings.defaultOnchainLivePriceIntervalSeconds) })
}

extension DependencyValues {
    var pricePollingSettings: PricePollingSettingsClient {
        get { self[PricePollingSettingsClient.self] }
        set { self[PricePollingSettingsClient.self] = newValue }
    }
}

// MARK: - ProviderSyncSettingsClient

struct ProviderSyncSettingsClient {
    var onchainPortfolioSyncInterval: @Sendable () -> Duration?
    var exchangePortfolioSyncInterval: @Sendable () -> Duration?
}

extension ProviderSyncSettingsClient: DependencyKey {
    static let liveValue = Self(
        onchainPortfolioSyncInterval: { ProviderIntervalSettings.onchainPortfolioSyncInterval() },
        exchangePortfolioSyncInterval: { ProviderIntervalSettings.exchangePortfolioSyncInterval() })
    static let testValue = Self(
        onchainPortfolioSyncInterval: { .seconds(ProviderIntervalSettings.defaultOnchainPortfolioSyncIntervalSeconds) },
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
