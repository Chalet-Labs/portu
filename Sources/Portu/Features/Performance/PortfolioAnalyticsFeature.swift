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
    let fallbackScopeFingerprint: String?

    init(
        scope: PortfolioAnalyticsScope,
        chartRange: ChartTimeRange,
        currency: FiatCurrency,
        implementations: [OnchainTokenIdentity],
        asOf: Date,
        isAccountActive: Bool = true,
        fallbackScopeFingerprint: String? = nil) {
        self.scope = scope
        self.chartRange = chartRange
        self.currency = currency
        self.implementations = implementations
        self.asOf = asOf
        self.isAccountActive = isAccountActive
        self.fallbackScopeFingerprint = fallbackScopeFingerprint
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
struct PortfolioAnalyticsFeature {
    @ObservableState
    struct State: Equatable {
        var isAvailable = false
        var pnlRange: ProviderPnLRange = .oneMonth
        var selectedWalletScopeFingerprint: String?
        var activeRequestID: String?
        var clearRequestGeneration: UInt = 0
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
    }

    @Dependency(\.date.now) var now
    @Dependency(\.portfolioAnalytics) var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .featureExited:
                state.fallbackScopeFingerprint = nil
                state.pnlRefreshAttemptID = nil
                return .none

            case .selectionUnavailable:
                state.selectedWalletScopeFingerprint = nil
                state.activeRequestID = nil
                state.fallbackScopeFingerprint = nil
                state.pnlRefreshAttemptID = nil
                state.history = []
                state.pnl = nil
                state.historyStatus = .idle
                state.pnlStatus = .idle
                return .merge(
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl))

            case let .load(context):
                if context.isAccountActive == false {
                    state.activeRequestID = nil
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
                        .cancel(id: CancelID.pnl))
                }
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
                    state.fallbackScopeFingerprint = nil
                    state.history = []
                    state.pnl = nil
                    state.historyStatus = .idle
                    state.pnlStatus = .idle
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl))
                }
                let requestID = context.requestID(pnlRange: state.pnlRange)
                state.fallbackScopeFingerprint = context.fallbackScopeFingerprint
                if state.activeRequestID != requestID {
                    state.pnl = nil
                }
                state.activeRequestID = requestID
                state.historyStatus = .loading
                state.pnlStatus = .loading
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
                return .merge(
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl),
                    cacheEffect)

            case let .refresh(context):
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
                    if state.historyStatus == .loading || state.historyStatus == .refreshing {
                        state.historyStatus = .idle
                    }
                    if state.pnlStatus == .loading || state.pnlStatus == .refreshing {
                        state.pnlStatus = .idle
                    }
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl))
                }
                state.refreshRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|refresh|\(state.refreshRequestGeneration)"
                state.fallbackScopeFingerprint = context.fallbackScopeFingerprint
                state.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                state.activeRequestID = requestID
                if Self.supportsProviderHistory(context) {
                    state.historyStatus = state.history.isEmpty ? .loading : .refreshing
                } else {
                    state.history = []
                    state.historyStatus = .idle
                }
                state.pnlStatus = state.pnl == nil ? .loading : .refreshing
                return refreshEffects(context: context, requestID: requestID, pnlRange: state.pnlRange)

            case let .refreshPnL(context):
                let context = context.stamped(at: now)
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
                    if state.historyStatus == .loading || state.historyStatus == .refreshing {
                        state.historyStatus = .idle
                    }
                    if state.pnlStatus == .loading || state.pnlStatus == .refreshing {
                        state.pnlStatus = .idle
                    }
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl))
                }
                state.refreshRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|pnl|\(state.refreshRequestGeneration)"
                state.fallbackScopeFingerprint = context.fallbackScopeFingerprint
                state.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                state.activeRequestID = requestID
                state.pnlStatus = state.pnl == nil ? .loading : .refreshing
                return pnlEffect(context: context, requestID: requestID, pnlRange: state.pnlRange)

            case let .clearCache(context):
                state.clearRequestGeneration &+= 1
                let requestID =
                    "\(context.requestID(pnlRange: state.pnlRange))|clear|\(state.clearRequestGeneration)"
                state.activeRequestID = requestID
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
                state.fallbackScopeFingerprint = nil
                state.pnlRefreshAttemptID = nil
                state.history = []
                state.pnl = nil
                state.historyStatus = .idle
                state.pnlStatus = .idle
                return .merge(
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl))

            case let .pnlRangeChanged(range, context):
                guard context.isAccountActive else { return .none }
                let context = context.stamped(at: now)
                state.pnlRange = range
                state.activeRequestID = nil
                state.pnl = nil
                state.pnlStatus = .idle
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.historyStatus = .idle
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl))
                }
                return .send(.load(context))

            case let .cacheLoaded(context, requestID, .success(cache)):
                guard requestID == state.activeRequestID else { return .none }
                let supportsProviderHistory = Self.supportsProviderHistory(context)
                state.history = supportsProviderHistory ? cache.history : []
                state.historyStatus = supportsProviderHistory ? .loaded : .idle
                state.pnl = cache.pnl

                let historyNeedsRefresh = supportsProviderHistory
                    && (cache.historyCoverageStartDate.map {
                        $0 > HistoricalPriceCalendar.utcStartOfDay(
                            for: context.chartRange.startDate(at: context.asOf))
                    } ?? true
                        || cache.historyFetchedAt.map {
                            context.asOf.timeIntervalSince($0) >= ProviderPnLFreshness.freshTTL
                        } ?? true)
                let pnlNeedsRefresh: Bool
                if let pnl = cache.pnl {
                    pnlNeedsRefresh = ProviderPnLFreshness.evaluate(
                        fetchedAt: pnl.fetchedAt,
                        now: context.asOf) != .fresh
                    state.pnlStatus = pnlNeedsRefresh ? .refreshing : .loaded
                } else {
                    pnlNeedsRefresh = true
                    state.pnlStatus = .loading
                }

                var effects: [Effect<Action>] = []
                if historyNeedsRefresh {
                    state.historyStatus = cache.history.isEmpty ? .loading : .refreshing
                    effects.append(historyEffect(context: context, requestID: requestID))
                }
                let pnlRefreshAttemptID = context.pnlRequestID(pnlRange: state.pnlRange)
                if pnlNeedsRefresh, state.pnlRefreshAttemptID != pnlRefreshAttemptID {
                    state.pnlRefreshAttemptID = pnlRefreshAttemptID
                    effects.append(pnlEffect(
                        context: context,
                        requestID: requestID,
                        pnlRange: state.pnlRange))
                } else if pnlNeedsRefresh {
                    state.pnlStatus = cache.pnl == nil ? .idle : .loaded
                }
                return .merge(effects)

            case let .cacheLoaded(_, requestID, .failure(error)):
                guard requestID == state.activeRequestID else { return .none }
                state.historyStatus = .failed(error.failure)
                state.pnlStatus = .failed(error.failure)
                return .none

            case let .historyResponse(requestID, .success(history)):
                guard requestID == state.activeRequestID else { return .none }
                state.history = history
                state.historyStatus = .loaded
                return .none

            case let .historyResponse(requestID, .failure(error)):
                guard requestID == state.activeRequestID else { return .none }
                if Self.selectFallbackIfAvailable(state: &state, failure: error.failure) {
                    return cancelAnalyticsEffects()
                }
                state.historyStatus = .failed(error.failure)
                return .none

            case let .pnlResponse(requestID, .success(pnl)):
                guard requestID == state.activeRequestID else { return .none }
                state.pnlRefreshAttemptID = nil
                state.pnl = pnl
                state.pnlStatus = .loaded
                return .none

            case let .pnlResponse(requestID, .failure(error)):
                guard requestID == state.activeRequestID else { return .none }
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
        context.chartRange != .custom
    }

    private static func selectFallbackIfAvailable(
        state: inout State,
        failure: PortfolioAnalyticsFailure) -> Bool {
        guard
            failure == .unavailableForScope,
            let fallback = state.fallbackScopeFingerprint else { return false }
        state.selectedWalletScopeFingerprint = fallback
        state.activeRequestID = nil
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
            .cancel(id: CancelID.pnl))
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
