import ComposableArchitecture
import Foundation
import os
import PortuCore
import PortuNetwork
import SwiftData

private let portfolioAnalyticsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app",
    category: "PortfolioAnalytics")

struct PortfolioAnalyticsCache: Equatable {
    let history: [ProviderPortfolioValueDTO]
    let historyFetchedAt: Date?
    let pnl: ProviderPnLDTO?

    static let empty = Self(history: [], historyFetchedAt: nil, pnl: nil)
}

enum PortfolioAnalyticsFailure: Error, Equatable {
    case preparing(retryAfter: Int?)
    case planUnavailable
    case invalidCredential
    case invalidRequest
    case unavailableForScope
    case rateLimited
    case unsupportedAggregation
    case generic(String)

    var message: String {
        switch self {
        case let .preparing(retryAfter):
            if let retryAfter {
                "Zerion is preparing this wallet. Retry in about \(retryAfter) seconds."
            } else {
                "Zerion is preparing this wallet. Try again shortly."
            }
        case .planUnavailable:
            "Your Zerion API plan does not include portfolio analytics. Other Portu features remain available."
        case .invalidCredential:
            "The Zerion API key is invalid. Update it in Settings."
        case .invalidRequest:
            "Zerion rejected this wallet or analytics request."
        case .unavailableForScope:
            "Zerion analytics are unavailable for this wallet scope."
        case .rateLimited:
            "The Zerion request quota is exhausted. Cached analytics remain available."
        case .unsupportedAggregation:
            "This wallet combination cannot be aggregated. Select an individual wallet."
        case let .generic(message):
            message
        }
    }
}

struct PortfolioAnalyticsClientError: Error, Equatable {
    let failure: PortfolioAnalyticsFailure

    var message: String {
        failure.message
    }

    init(_ error: any Error) {
        guard let error = error as? ZerionError else {
            self.failure = .generic(error.localizedDescription)
            return
        }
        if case let .apiError(statusCode, _, _) = error {
            self.failure = Self.failure(
                forAPIStatusCode: statusCode,
                fallbackMessage: error.localizedDescription)
            return
        }
        self.failure = switch error {
        case let .temporarilyUnavailable(retryAfter):
            .preparing(retryAfter: retryAfter)
        case .paymentRequired:
            .planUnavailable
        case .unauthorized, .missingAPIKey:
            .invalidCredential
        case .badRequest, .invalidAddress, .invalidData, .unsupportedChain:
            .invalidRequest
        case .notFound:
            .unavailableForScope
        case .rateLimited:
            .rateLimited
        case .unsupportedAnalyticsScope:
            .unsupportedAggregation
        case .apiError:
            .generic(error.localizedDescription)
        case .untrustedURL, .invalidResponse, .httpError, .decodingFailed:
            .generic(error.localizedDescription)
        }
    }

    private static func failure(
        forAPIStatusCode statusCode: Int,
        fallbackMessage: String) -> PortfolioAnalyticsFailure {
        switch statusCode {
        case 400: .invalidRequest
        case 401, 403: .invalidCredential
        case 402: .planUnavailable
        case 404: .unavailableForScope
        case 429: .rateLimited
        case 503: .preparing(retryAfter: nil)
        default: .generic(fallbackMessage)
        }
    }
}

struct PortfolioAnalyticsClient {
    var loadCache: @MainActor @Sendable (
        PortfolioAnalyticsScope,
        ProviderPnLRange,
        FiatCurrency) async throws -> PortfolioAnalyticsCache
    var refreshHistory: @MainActor @Sendable (
        PortfolioAnalyticsScope,
        ChartTimeRange) async throws -> [ProviderPortfolioValueDTO]
    var refreshPnL: @MainActor @Sendable (
        PortfolioAnalyticsScope,
        ProviderPnLRange,
        FiatCurrency,
        [OnchainTokenIdentity],
        Date) async throws -> ProviderPnLDTO
    var clearAccountCache: @MainActor @Sendable (UUID) async throws -> Int
}

enum PortfolioAnalyticsFeatureFlag {
    static let defaultsKey = "portfolioAnalyticsEnabled"

    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard) -> Bool {
        environment["PORTU_ZERION_ANALYTICS"] == "1"
            || defaults.bool(forKey: defaultsKey)
    }
}

extension PortfolioAnalyticsClient: DependencyKey {
    static let liveValue = Self(
        loadCache: { _, _, _ in
            fatalError("PortfolioAnalyticsClient.liveValue must be overridden at Store creation")
        },
        refreshHistory: { _, _ in
            fatalError("PortfolioAnalyticsClient.liveValue must be overridden at Store creation")
        },
        refreshPnL: { _, _, _, _, _ in
            fatalError("PortfolioAnalyticsClient.liveValue must be overridden at Store creation")
        },
        clearAccountCache: { _ in
            fatalError("PortfolioAnalyticsClient.liveValue must be overridden at Store creation")
        })

    static let testValue = Self(
        loadCache: { _, _, _ in .empty },
        refreshHistory: { _, _ in [] },
        refreshPnL: { _, range, currency, _, date in
            ProviderPnLDTO(
                range: range,
                currency: currency,
                totalGain: 0,
                fetchedAt: date)
        },
        clearAccountCache: { _ in 0 })
}

extension DependencyValues {
    var portfolioAnalytics: PortfolioAnalyticsClient {
        get { self[PortfolioAnalyticsClient.self] }
        set { self[PortfolioAnalyticsClient.self] = newValue }
    }
}

extension PortfolioAnalyticsClient {
    @MainActor
    static func live(
        modelContext: ModelContext,
        service: any ZerionAnalyticsService,
        now: @escaping @Sendable () -> Date = { .now }) -> Self {
        Self(
            loadCache: { scope, range, currency in
                try loadCachedAnalytics(
                    scope: scope,
                    range: range,
                    currency: currency,
                    modelContext: modelContext)
            },
            refreshHistory: { scope, chartRange in
                let period: ZerionChartPeriod = switch chartRange {
                case .oneWeek: .week
                case .oneMonth: .month
                case .threeMonths: .threeMonths
                case .oneYear: .year
                case .ytd: .yearToDate(at: now())
                case .custom: .month
                }
                let history = try await service.fetchPortfolioValueHistory(
                    scope: scope,
                    period: period)
                let write = try PortfolioAnalyticsCacheWriter.upsertHistory(
                    history,
                    scope: scope,
                    in: modelContext,
                    fetchedAt: now())
                let accountID = scope.accountID.uuidString
                let scopeID = String(scope.fingerprint.prefix(12))
                let pointCount = history.count
                let insertedCount = write.inserted
                let updatedCount = write.updated
                portfolioAnalyticsLogger.info(
                    "History account=\(accountID, privacy: .public) scope=\(scopeID, privacy: .public) points=\(pointCount, privacy: .public)")
                portfolioAnalyticsLogger.info(
                    "History new=\(insertedCount, privacy: .public) changed=\(updatedCount, privacy: .public)")
                return history
            },
            refreshPnL: { scope, range, currency, implementations, asOf in
                let pnl = try await service.fetchPnL(
                    scope: scope,
                    range: range,
                    currency: currency,
                    implementations: implementations,
                    asOf: asOf)
                try PortfolioAnalyticsCacheWriter.upsertPnL(
                    pnl,
                    scope: scope,
                    in: modelContext)
                let accountID = scope.accountID.uuidString
                let scopeID = String(scope.fingerprint.prefix(12))
                let assetCount = pnl.assets.count
                let excludedCount = pnl.excludedIdentifiers.count
                portfolioAnalyticsLogger.info(
                    "PnL account=\(accountID, privacy: .public) scope=\(scopeID, privacy: .public)")
                portfolioAnalyticsLogger.info(
                    "PnL assets=\(assetCount, privacy: .public) excluded=\(excludedCount, privacy: .public)")
                return pnl
            },
            clearAccountCache: { accountID in
                let removed = try PortfolioAnalyticsCacheWriter.clear(
                    accountID: accountID,
                    in: modelContext)
                portfolioAnalyticsLogger.info(
                    "Analytics cache cleared account=\(accountID.uuidString, privacy: .public) rows=\(removed, privacy: .public)")
                return removed
            })
    }

    @MainActor
    private static func loadCachedAnalytics(
        scope: PortfolioAnalyticsScope,
        range: ProviderPnLRange,
        currency: FiatCurrency,
        modelContext: ModelContext) throws -> PortfolioAnalyticsCache {
        let accountID = scope.accountID
        let historyRows = try modelContext.fetch(
            FetchDescriptor<ProviderPortfolioValuePoint>(
                predicate: #Predicate { $0.accountID == accountID }))
            .filter {
                $0.scopeFingerprint == scope.fingerprint
                    && $0.provider == .zerion
            }
            .sorted {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp < $1.timestamp
                }
                return $0.cacheKey < $1.cacheKey
            }
        let cacheKey = ProviderPnLSnapshot.cacheKey(
            accountID: scope.accountID,
            scopeFingerprint: scope.fingerprint,
            provider: .zerion,
            range: range,
            currency: currency)
        let pnl = try modelContext.fetch(FetchDescriptor<ProviderPnLSnapshot>(
            predicate: #Predicate { $0.cacheKey == cacheKey })).first
        return PortfolioAnalyticsCache(
            history: historyRows.map {
                ProviderPortfolioValueDTO(
                    timestamp: $0.timestamp,
                    usdValue: $0.usdValue,
                    provider: $0.provider,
                    coverage: $0.coverage)
            },
            historyFetchedAt: historyRows.map(\.fetchedAt).max(),
            pnl: pnl.map(providerPnLDTO))
    }

    @MainActor
    private static func providerPnLDTO(_ snapshot: ProviderPnLSnapshot) -> ProviderPnLDTO {
        ProviderPnLDTO(
            range: snapshot.range,
            currency: snapshot.currency,
            totalGain: snapshot.totalGain,
            realizedGain: snapshot.realizedGain,
            unrealizedGain: snapshot.unrealizedGain,
            relativeTotalGain: snapshot.relativeTotalGain,
            relativeRealizedGain: snapshot.relativeRealizedGain,
            relativeUnrealizedGain: snapshot.relativeUnrealizedGain,
            totalFee: snapshot.totalFee,
            totalInvested: snapshot.totalInvested,
            realizedCostBasis: snapshot.realizedCostBasis,
            netInvested: snapshot.netInvested,
            receivedExternal: snapshot.receivedExternal,
            sentExternal: snapshot.sentExternal,
            sentForNFTs: snapshot.sentForNFTs,
            receivedForNFTs: snapshot.receivedForNFTs,
            excludedIdentifiers: snapshot.excludedIdentifiers,
            assets: snapshot.assetBreakdowns.map {
                ProviderPnLAssetDTO(
                    implementationID: $0.implementationID,
                    identity: $0.identity,
                    averageBuyPrice: $0.averageBuyPrice,
                    averageSellPrice: $0.averageSellPrice,
                    totalGain: $0.totalGain,
                    realizedGain: $0.realizedGain,
                    unrealizedGain: $0.unrealizedGain,
                    relativeTotalGain: $0.relativeTotalGain,
                    relativeRealizedGain: $0.relativeRealizedGain,
                    relativeUnrealizedGain: $0.relativeUnrealizedGain,
                    totalFee: $0.totalFee,
                    totalInvested: $0.totalInvested,
                    realizedCostBasis: $0.realizedCostBasis,
                    netInvested: $0.netInvested,
                    receivedExternal: $0.receivedExternal,
                    sentExternal: $0.sentExternal,
                    sentForNFTs: $0.sentForNFTs,
                    receivedForNFTs: $0.receivedForNFTs)
            },
            fetchedAt: snapshot.fetchedAt)
    }
}
