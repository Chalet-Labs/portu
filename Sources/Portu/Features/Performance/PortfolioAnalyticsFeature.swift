// swiftlint:disable file_length

import ComposableArchitecture
import Foundation
import PortuCore

struct PortfolioAnalyticsRequestContext: Equatable {
    let scope: PortfolioAnalyticsScope
    let chartRange: ChartTimeRange
    let currency: FiatCurrency
    let implementations: [OnchainTokenIdentity]
    let asOf: Date
    let isAccountActive: Bool
    let isFullAccountScope: Bool
    let fallbackScopeFingerprint: String?

    init(
        scope: PortfolioAnalyticsScope,
        chartRange: ChartTimeRange,
        currency: FiatCurrency,
        implementations: [OnchainTokenIdentity],
        asOf: Date,
        isAccountActive: Bool = true,
        isFullAccountScope: Bool = true,
        fallbackScopeFingerprint: String? = nil) {
        self.scope = scope
        self.chartRange = chartRange
        self.currency = currency
        self.implementations = implementations
        self.asOf = asOf
        self.isAccountActive = isAccountActive
        self.isFullAccountScope = isFullAccountScope
        self.fallbackScopeFingerprint = fallbackScopeFingerprint
    }

    var historyRequestID: String {
        [
            scope.fingerprint,
            chartRange.rawValue,
            currency.rawValue
        ].joined(separator: "|")
    }

    func requestID(pnlRange: ProviderPnLRange) -> String {
        [
            scope.fingerprint,
            chartRange.rawValue,
            pnlRange.rawValue,
            currency.rawValue
        ].joined(separator: "|")
    }

    func pnlRequestID(pnlRange: ProviderPnLRange) -> String {
        [
            scope.fingerprint,
            pnlRange.rawValue,
            currency.rawValue
        ].joined(separator: "|")
    }

    func stamped(at date: Date) -> Self {
        Self(
            scope: scope,
            chartRange: chartRange,
            currency: currency,
            implementations: implementations,
            asOf: date,
            isAccountActive: isAccountActive,
            isFullAccountScope: isFullAccountScope,
            fallbackScopeFingerprint: fallbackScopeFingerprint)
    }
}

enum PortfolioAnalyticsLoadStatus: Equatable {
    case idle
    case loading
    case refreshing
    case loaded
    case failed(PortfolioAnalyticsFailure)
}

@Reducer
// swiftlint:disable:next type_body_length
struct PortfolioAnalyticsFeature {
    @ObservableState
    struct State: Equatable {
        var isAvailable = false
        var pnlRange: ProviderPnLRange = .oneMonth
        var selectedWalletScopeFingerprint: String?
        var activeRequestID: String?
        var activeHistoryRequestID: String?
        var activePnLRequestID: String?
        var clearRequestGeneration: UInt = 0
        var loadRequestGeneration: UInt = 0
        var refreshRequestGeneration: UInt = 0
        var fallbackScopeFingerprint: String?
        var pnlRefreshAttemptID: String?
        var history: [ProviderPortfolioValueDTO] = []
        var pnl: ProviderPnLDTO?
        var historyStatus: PortfolioAnalyticsLoadStatus = .idle
        var pnlStatus: PortfolioAnalyticsLoadStatus = .idle
    }

    enum Action: Equatable {
        case featureExited
        case load(PortfolioAnalyticsRequestContext)
        case selectionUnavailable
        case refresh(PortfolioAnalyticsRequestContext)
        case refreshPnL(PortfolioAnalyticsRequestContext)
        case clearCache(PortfolioAnalyticsRequestContext)
        case clearCacheResponse(String, Result<Int, PortfolioAnalyticsClientError>)
        case walletScopeSelected(String)
        case pnlRangeChanged(ProviderPnLRange, PortfolioAnalyticsRequestContext)
        case cacheLoaded(
            PortfolioAnalyticsRequestContext,
            String,
            Result<PortfolioAnalyticsCache, PortfolioAnalyticsClientError>)
        case pnlCacheLoaded(
            PortfolioAnalyticsRequestContext,
            String,
            Result<PortfolioAnalyticsCache, PortfolioAnalyticsClientError>)
        case historyResponse(
            String,
            Result<[ProviderPortfolioValueDTO], PortfolioAnalyticsClientError>)
        case pnlResponse(
            String,
            Result<ProviderPnLDTO, PortfolioAnalyticsClientError>)
    }

    private enum CancelID {
        case cache
        case history
        case pnl
        case pnlCache
    }

    @Dependency(\.date.now) var now
    @Dependency(\.portfolioAnalytics) var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .featureExited:
                state.activeRequestID = nil
                state.activeHistoryRequestID = nil
                state.activePnLRequestID = nil
                state.fallbackScopeFingerprint = nil
                state.pnlRefreshAttemptID = nil
                if state.historyStatus == .loading || state.historyStatus == .refreshing {
                    state.historyStatus = .idle
                }
                if state.pnlStatus == .loading || state.pnlStatus == .refreshing {
                    state.pnlStatus = .idle
                }
                return cancelAnalyticsEffects()

            case .selectionUnavailable:
                state.selectedWalletScopeFingerprint = nil
                state.activeRequestID = nil
                state.activeHistoryRequestID = nil
                state.activePnLRequestID = nil
                state.fallbackScopeFingerprint = nil
                state.pnlRefreshAttemptID = nil
                state.history = []
                state.pnl = nil
                state.historyStatus = .idle
                state.pnlStatus = .idle
                return .merge(
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl),
                    .cancel(id: CancelID.pnlCache))

            case let .load(context):
                if context.isAccountActive == false {
                    state.activeRequestID = nil
                    state.activeHistoryRequestID = nil
                    state.activePnLRequestID = nil
                    state.fallbackScopeFingerprint = nil
                    if state.historyStatus == .loading || state.historyStatus == .refreshing {
                        state.historyStatus = .idle
                    }
                    if state.pnlStatus == .loading || state.pnlStatus == .refreshing {
                        state.pnlStatus = .idle
                    }
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl),
                        .cancel(id: CancelID.pnlCache))
                }
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
                    state.activeHistoryRequestID = nil
                    state.activePnLRequestID = nil
                    state.fallbackScopeFingerprint = nil
                    state.history = []
                    state.pnl = nil
                    state.historyStatus = .idle
                    state.pnlStatus = .idle
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl),
                        .cancel(id: CancelID.pnlCache))
                }
                let samePnLIdentity =
                    state.pnlRefreshAttemptID == context.pnlRequestID(pnlRange: state.pnlRange)
                let preservePnLRefresh = state.activePnLRequestID != nil && samePnLIdentity
                state.loadRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|load|\(state.loadRequestGeneration)"
                state.fallbackScopeFingerprint = context.fallbackScopeFingerprint
                state.activeHistoryRequestID = nil
                if samePnLIdentity == false {
                    state.activePnLRequestID = nil
                    state.pnlRefreshAttemptID = nil
                }
                if state.activeRequestID != requestID, preservePnLRefresh == false {
                    state.pnl = nil
                }
                state.activeRequestID = requestID
                state.historyStatus = .loading
                if preservePnLRefresh == false {
                    state.pnlStatus = .loading
                }
                let pnlRange = state.pnlRange
                let cacheEffect = Effect<Action>.run { send in
                    do {
                        let cache = try await client.loadCache(
                            context.scope,
                            pnlRange,
                            context.currency,
                            context.chartRange.startDate(at: context.asOf))
                        await send(.cacheLoaded(context, requestID, .success(cache)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.cacheLoaded(
                            context,
                            requestID,
                            .failure(PortfolioAnalyticsClientError(error))))
                    }
                }
                .cancellable(id: CancelID.cache, cancelInFlight: true)
                var effects: [Effect<Action>] = [
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnlCache),
                    cacheEffect
                ]
                if preservePnLRefresh == false {
                    effects.insert(.cancel(id: CancelID.pnl), at: 1)
                }
                return .merge(effects)

            case let .refresh(context):
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
                    state.activeHistoryRequestID = nil
                    state.activePnLRequestID = nil
                    if state.historyStatus == .loading || state.historyStatus == .refreshing {
                        state.historyStatus = .idle
                    }
                    if state.pnlStatus == .loading || state.pnlStatus == .refreshing {
                        state.pnlStatus = .idle
                    }
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl),
                        .cancel(id: CancelID.pnlCache))
                }
                state.refreshRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|refresh|\(state.refreshRequestGeneration)"
                state.fallbackScopeFingerprint = context.fallbackScopeFingerprint
                state.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                state.activeRequestID = requestID
                state.activePnLRequestID = requestID
                if Self.supportsProviderHistory(context) {
                    state.activeHistoryRequestID = requestID
                    state.historyStatus = state.history.isEmpty ? .loading : .refreshing
                } else {
                    state.activeHistoryRequestID = nil
                    state.history = []
                    state.historyStatus = .idle
                }
                state.pnlStatus = state.pnl == nil ? .loading : .refreshing
                return refreshEffects(context: context, requestID: requestID, pnlRange: state.pnlRange)

            case let .refreshPnL(context):
                let context = context.stamped(at: now)
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
                    state.activeHistoryRequestID = nil
                    state.activePnLRequestID = nil
                    if state.historyStatus == .loading || state.historyStatus == .refreshing {
                        state.historyStatus = .idle
                    }
                    if state.pnlStatus == .loading || state.pnlStatus == .refreshing {
                        state.pnlStatus = .idle
                    }
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl),
                        .cancel(id: CancelID.pnlCache))
                }
                state.refreshRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|pnl|\(state.refreshRequestGeneration)"
                state.fallbackScopeFingerprint = context.fallbackScopeFingerprint
                state.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                state.activePnLRequestID = requestID
                state.pnlStatus = state.pnl == nil ? .loading : .refreshing
                return pnlEffect(context: context, requestID: requestID, pnlRange: state.pnlRange)

            case let .clearCache(context):
                state.clearRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|clear|\(state.clearRequestGeneration)"
                state.activeRequestID = requestID
                state.activeHistoryRequestID = nil
                state.activePnLRequestID = nil
                state.pnlRefreshAttemptID = nil
                let clearEffect = Effect<Action>.run { send in
                    do {
                        let count = try await client.clearAccountCache(context.scope.accountID)
                        await send(.clearCacheResponse(requestID, .success(count)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.clearCacheResponse(
                            requestID,
                            .failure(PortfolioAnalyticsClientError(error))))
                    }
                }
                .cancellable(id: CancelID.cache, cancelInFlight: true)
                return .merge(
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl),
                    .cancel(id: CancelID.pnlCache),
                    clearEffect)

            case let .clearCacheResponse(requestID, .success):
                guard requestID == state.activeRequestID else { return .none }
                state.history = []
                state.pnl = nil
                state.historyStatus = .idle
                state.pnlStatus = .idle
                return .none

            case let .clearCacheResponse(requestID, .failure(error)):
                guard requestID == state.activeRequestID else { return .none }
                state.historyStatus = .failed(error.failure)
                state.pnlStatus = .failed(error.failure)
                return .none

            case let .walletScopeSelected(fingerprint):
                state.selectedWalletScopeFingerprint = fingerprint
                state.activeRequestID = nil
                state.activeHistoryRequestID = nil
                state.activePnLRequestID = nil
                state.fallbackScopeFingerprint = nil
                state.pnlRefreshAttemptID = nil
                state.history = []
                state.pnl = nil
                state.historyStatus = .idle
                state.pnlStatus = .idle
                return .merge(
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl),
                    .cancel(id: CancelID.pnlCache))

            case let .pnlRangeChanged(range, context):
                guard context.isAccountActive else { return .none }
                let context = context.stamped(at: now)
                state.pnlRange = range
                state.pnl = nil
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.pnlStatus = .idle
                    return .merge(
                        .cancel(id: CancelID.pnlCache),
                        .cancel(id: CancelID.pnl))
                }
                state.loadRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: range))|pnl-load|\(state.loadRequestGeneration)"
                state.activePnLRequestID = requestID
                state.pnlRefreshAttemptID = nil
                state.pnlStatus = .loading
                let cacheEffect = Effect<Action>.run { send in
                    do {
                        let cache = try await client.loadCache(
                            context.scope,
                            range,
                            context.currency,
                            context.chartRange.startDate(at: context.asOf))
                        await send(.pnlCacheLoaded(context, requestID, .success(cache)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.pnlCacheLoaded(
                            context,
                            requestID,
                            .failure(PortfolioAnalyticsClientError(error))))
                    }
                }
                .cancellable(id: CancelID.pnlCache, cancelInFlight: true)
                return .merge(.cancel(id: CancelID.pnl), cacheEffect)

            case let .cacheLoaded(context, requestID, .success(cache)):
                guard requestID == state.activeRequestID else { return .none }
                let supportsProviderHistory = Self.supportsProviderHistory(context)
                state.history = supportsProviderHistory ? cache.history : []
                state.historyStatus = supportsProviderHistory ? .loaded : .idle
                let shouldApplyPnL = state.activePnLRequestID == nil
                if shouldApplyPnL {
                    state.pnl = cache.pnl
                }

                let historyNeedsRefresh = supportsProviderHistory
                    && (cache.historyCoverageStartDate.map {
                        $0 > HistoricalPriceCalendar.utcStartOfDay(
                            for: context.chartRange.startDate(at: context.asOf))
                    } ?? true
                        || cache.historyFetchedAt.map {
                            context.asOf.timeIntervalSince($0) >= ProviderPnLFreshness.freshTTL
                        } ?? true)
                let pnlNeedsRefresh: Bool
                if shouldApplyPnL {
                    if let pnl = cache.pnl {
                        pnlNeedsRefresh = ProviderPnLFreshness.evaluate(
                            fetchedAt: pnl.fetchedAt,
                            now: context.asOf) != .fresh
                        state.pnlStatus = pnlNeedsRefresh ? .refreshing : .loaded
                    } else {
                        pnlNeedsRefresh = true
                        state.pnlStatus = .loading
                    }
                } else {
                    pnlNeedsRefresh = false
                }

                var effects: [Effect<Action>] = []
                if historyNeedsRefresh {
                    state.historyStatus = cache.history.isEmpty ? .loading : .refreshing
                    state.activeHistoryRequestID = requestID
                    effects.append(historyEffect(context: context, requestID: requestID))
                } else {
                    state.activeHistoryRequestID = nil
                }
                let pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                if pnlNeedsRefresh, state.pnlRefreshAttemptID != pnlRefreshAttemptID {
                    state.pnlRefreshAttemptID = pnlRefreshAttemptID
                    state.activePnLRequestID = requestID
                    effects.append(pnlEffect(
                        context: context,
                        requestID: requestID,
                        pnlRange: state.pnlRange))
                } else if pnlNeedsRefresh {
                    state.pnlStatus = cache.pnl == nil ? .idle : .loaded
                }
                return .merge(effects)

            case let .pnlCacheLoaded(context, requestID, .success(cache)):
                guard requestID == state.activePnLRequestID else { return .none }
                state.pnl = cache.pnl
                if
                    let pnl = cache.pnl,
                    ProviderPnLFreshness.evaluate(
                        fetchedAt: pnl.fetchedAt,
                        now: context.asOf) == .fresh {
                    state.activePnLRequestID = nil
                    state.pnlStatus = .loaded
                    return .none
                }
                state.pnlStatus = cache.pnl == nil ? .loading : .refreshing
                state.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                return pnlEffect(
                    context: context,
                    requestID: requestID,
                    pnlRange: state.pnlRange)

            case let .pnlCacheLoaded(_, requestID, .failure(error)):
                guard requestID == state.activePnLRequestID else { return .none }
                state.activePnLRequestID = nil
                state.pnlStatus = .failed(error.failure)
                return .none

            case let .cacheLoaded(_, requestID, .failure(error)):
                guard requestID == state.activeRequestID else { return .none }
                state.historyStatus = .failed(error.failure)
                if state.activePnLRequestID == nil {
                    state.pnlStatus = .failed(error.failure)
                }
                return .none

            case let .historyResponse(requestID, .success(history)):
                guard requestID == state.activeHistoryRequestID else { return .none }
                state.activeHistoryRequestID = nil
                state.history = history
                state.historyStatus = .loaded
                return .none

            case let .historyResponse(requestID, .failure(error)):
                guard requestID == state.activeHistoryRequestID else { return .none }
                state.activeHistoryRequestID = nil
                if Self.selectFallbackIfAvailable(state: &state, failure: error.failure) {
                    return cancelAnalyticsEffects()
                }
                state.historyStatus = .failed(error.failure)
                return .none

            case let .pnlResponse(requestID, .success(pnl)):
                guard requestID == state.activePnLRequestID else { return .none }
                state.activePnLRequestID = nil
                state.pnlRefreshAttemptID = nil
                state.pnl = pnl
                state.pnlStatus = .loaded
                return .none

            case let .pnlResponse(requestID, .failure(error)):
                guard requestID == state.activePnLRequestID else { return .none }
                state.activePnLRequestID = nil
                if Self.selectFallbackIfAvailable(state: &state, failure: error.failure) {
                    return cancelAnalyticsEffects()
                }
                state.pnlStatus = .failed(error.failure)
                return .none
            }
        }
    }

    private static func isEligible(
        _ context: PortfolioAnalyticsRequestContext,
        isAvailable: Bool) -> Bool {
        isAvailable
            && context.isAccountActive
            && context.scope.dataSource == .zerion
            && context.scope.addresses.isEmpty == false
    }

    private static func supportsProviderHistory(
        _ context: PortfolioAnalyticsRequestContext) -> Bool {
        context.chartRange != .custom && context.isFullAccountScope
    }

    private static func selectFallbackIfAvailable(
        state: inout State,
        failure: PortfolioAnalyticsFailure) -> Bool {
        guard
            failure == .unavailableForScope,
            let fallback = state.fallbackScopeFingerprint else { return false }
        state.selectedWalletScopeFingerprint = fallback
        state.activeRequestID = nil
        state.activeHistoryRequestID = nil
        state.activePnLRequestID = nil
        state.fallbackScopeFingerprint = nil
        state.pnlRefreshAttemptID = nil
        state.history = []
        state.pnl = nil
        state.historyStatus = .idle
        state.pnlStatus = .idle
        return true
    }

    private func cancelAnalyticsEffects() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.cache),
            .cancel(id: CancelID.history),
            .cancel(id: CancelID.pnl),
            .cancel(id: CancelID.pnlCache))
    }

    private func refreshEffects(
        context: PortfolioAnalyticsRequestContext,
        requestID: String,
        pnlRange: ProviderPnLRange) -> Effect<Action> {
        if Self.supportsProviderHistory(context) {
            return .merge(
                historyEffect(context: context, requestID: requestID),
                pnlEffect(context: context, requestID: requestID, pnlRange: pnlRange))
        }
        return pnlEffect(context: context, requestID: requestID, pnlRange: pnlRange)
    }

    private func historyEffect(
        context: PortfolioAnalyticsRequestContext,
        requestID: String) -> Effect<Action> {
        .run { send in
            do {
                let history = try await client.refreshHistory(context.scope, context.chartRange)
                await send(.historyResponse(requestID, .success(history)))
            } catch is CancellationError {
                return
            } catch {
                await send(.historyResponse(
                    requestID,
                    .failure(PortfolioAnalyticsClientError(error))))
            }
        }
        .cancellable(id: CancelID.history, cancelInFlight: true)
    }

    private func pnlEffect(
        context: PortfolioAnalyticsRequestContext,
        requestID: String,
        pnlRange: ProviderPnLRange) -> Effect<Action> {
        .run { send in
            do {
                let pnl = try await client.refreshPnL(
                    context.scope,
                    pnlRange,
                    context.currency,
                    context.implementations,
                    context.asOf)
                await send(.pnlResponse(requestID, .success(pnl)))
            } catch is CancellationError {
                return
            } catch {
                await send(.pnlResponse(
                    requestID,
                    .failure(PortfolioAnalyticsClientError(error))))
            }
        }
        .cancellable(id: CancelID.pnl, cancelInFlight: true)
    }
}
