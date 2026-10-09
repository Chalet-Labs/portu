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

/// What a sync completion action carries on failure. It keeps the engine's `SyncError`
/// when there is one, because `allAccountsFailed` settles an account sync differently
/// from every other failure.
struct SyncFailure: LocalizedError, Equatable {
    let message: String
    let syncError: SyncError?

    var errorDescription: String? {
        message
    }

    init(message: String, syncError: SyncError? = nil) {
        self.message = message
        self.syncError = syncError
    }

    init(_ error: any Error) {
        self.init(message: error.localizedDescription, syncError: error as? SyncError)
    }
}

/// How far a sync run has got. A run has one step per syncable account in it, plus one
/// for the snapshot that ends it.
struct SyncProgress: Equatable {
    let completedSteps: Int
    let totalSteps: Int

    init(completedSteps: Int, totalSteps: Int) {
        precondition(totalSteps >= 1, "A sync run has at least its snapshot step")
        precondition((0 ... totalSteps).contains(completedSteps), "Completed steps must lie within the run")
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
    }

    var fractionCompleted: Double {
        Double(completedSteps) / Double(totalSteps)
    }
}

typealias SyncProgressHandler = @Sendable (SyncProgress) async -> Void

/// Each sync reports its progress through the handler passed to that call: in step order,
/// awaiting each report, and all of them before the call returns or throws. The handler is
/// never kept or called from another task, so no progress from a run can reach the reducer
/// after that run's completion. Keep this when the engine moves off the main actor.
struct SyncEngineClient {
    var sync: @Sendable (_ progress: SyncProgressHandler) async throws -> SyncResult
    var syncScope: @Sendable (PortfolioSyncScope, _ progress: SyncProgressHandler) async throws -> SyncResult
    var syncAccount: @Sendable (UUID, _ progress: SyncProgressHandler) async throws -> SyncResult

    init(
        sync: @escaping @Sendable (_ progress: SyncProgressHandler) async throws -> SyncResult,
        syncScope: @escaping @Sendable (PortfolioSyncScope, _ progress: SyncProgressHandler) async throws -> SyncResult = { _, _ in
            SyncResult(failedAccounts: [])
        },
        syncAccount: @escaping @Sendable (UUID, _ progress: SyncProgressHandler) async throws -> SyncResult = { _, _ in
            SyncResult(failedAccounts: [])
        }) {
        self.sync = sync
        self.syncScope = syncScope
        self.syncAccount = syncAccount
    }
}

extension SyncEngineClient: DependencyKey {
    static let liveValue = Self(
        sync: { _ in fatalError("SyncEngineClient.liveValue must be overridden at Store creation") },
        syncScope: { _, _ in fatalError("SyncEngineClient.liveValue must be overridden at Store creation") },
        syncAccount: { _, _ in fatalError("SyncEngineClient.liveValue must be overridden at Store creation") })
    static let testValue = Self(
        sync: { _ in SyncResult(failedAccounts: []) },
        syncScope: { _, _ in SyncResult(failedAccounts: []) },
        syncAccount: { _, _ in SyncResult(failedAccounts: []) })

    static func live(engine: SyncEngine) -> Self {
        Self(
            sync: { progress in try await engine.sync(progress: progress) },
            syncScope: { scope, progress in try await engine.sync(scope: scope, progress: progress) },
            syncAccount: { accountID, progress in try await engine.sync(accountID: accountID, progress: progress) })
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

struct PriceFetchFailure: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }

    init(message: String) {
        self.message = message
    }

    init(_ error: any Error) {
        self.init(message: error.localizedDescription)
    }
}

struct PriceServiceClient {
    enum ClientError: Error {
        /// Returned by `fetchOnchainHistoricalPrices` when no Zerion API key is configured.
        /// The backfill runner's upstream pre-filter normally prevents reaching this path,
        /// but a missing key here means the candidate cannot be fetched — surface it as a
        /// failure instead of silently returning an empty result set.
        case onchainProviderUnavailable
    }

    var fetchPrices: @Sendable ([String]) async throws -> PriceUpdate
    private var fetchCoinGeckoPricesOverride: (@Sendable (PricePollingRequest) async throws -> PriceUpdate)?
    private var fetchOnchainFallbackPricesOverride: (@Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate?)?
    var fetchHistoricalPrices: @Sendable (String, Int) async throws -> [HistoricalPriceDTO]
    var fetchHistoricalPricesForCurrency: @Sendable (String, FiatCurrency, Int) async throws -> [HistoricalPriceDTO]
    var fetchCurrentUSDConversionRate: @Sendable (FiatCurrency) async throws -> Decimal
    var fetchHistoricalUSDConversionRates: @Sendable (FiatCurrency, Int) async throws -> [CurrencyConversionRate]
    var resolveCoinGeckoIDs: @Sendable ([OnchainTokenIdentity]) async throws -> [OnchainTokenIdentity: String]
    var fetchOnchainHistoricalPrices: @Sendable (OnchainTokenIdentity, Int) async throws -> [HistoricalPriceDTO]
    var canFetchOnchainHistoricalPrices: @Sendable () async throws -> Bool
    var invalidateCache: @Sendable () async -> Void

    /// Live price polling fetches. Both return USD prices: the display rate is applied
    /// where prices are shown, so these never take a currency or a rate.
    var fetchCoinGeckoPrices: @Sendable (PricePollingRequest) async throws -> PriceUpdate {
        get {
            if let fetchCoinGeckoPricesOverride {
                return fetchCoinGeckoPricesOverride
            }
            let fetchPrices = fetchPrices
            return { request in try await fetchPrices(request.allPriceIDs) }
        }
        set { fetchCoinGeckoPricesOverride = newValue }
    }

    /// The onchain fallback answers nil when it fetched nothing (no provider key), which the
    /// polling loop does not count as a fetch.
    var fetchOnchainFallbackPrices: @Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate? {
        get {
            if let fetchOnchainFallbackPricesOverride {
                return fetchOnchainFallbackPricesOverride
            }
            let fetchPrices = fetchPrices
            return { identities in try await fetchPrices(identities.map(\.historicalPriceID)) }
        }
        set { fetchOnchainFallbackPricesOverride = newValue }
    }

    init(
        fetchPrices: @escaping @Sendable ([String]) async throws -> PriceUpdate,
        fetchCoinGeckoPrices: (@Sendable (PricePollingRequest) async throws -> PriceUpdate)? = nil,
        fetchOnchainFallbackPrices: (@Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate?)? = nil,
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
        fetchCoinGeckoPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
        fetchOnchainFallbackPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
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
