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

    init(
        scope: PortfolioAnalyticsScope,
        chartRange: ChartTimeRange,
        currency: FiatCurrency,
        implementations: [OnchainTokenIdentity],
        asOf: Date,
        isAccountActive: Bool = true) {
        self.scope = scope
        self.chartRange = chartRange
        self.currency = currency
        self.implementations = implementations
        self.asOf = asOf
        self.isAccountActive = isAccountActive
    }

    func requestID(pnlRange: ProviderPnLRange) -> String {
        [
            scope.fingerprint,
            chartRange.rawValue,
            pnlRange.rawValue,
            currency.rawValue
        ].joined(separator: "|")
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
        var history: [ProviderPortfolioValueDTO] = []
        var pnl: ProviderPnLDTO?
        var historyStatus: PortfolioAnalyticsLoadStatus = .idle
        var pnlStatus: PortfolioAnalyticsLoadStatus = .idle
    }

    enum Action: Equatable {
        case load(PortfolioAnalyticsRequestContext)
        case selectionUnavailable
        case refresh(PortfolioAnalyticsRequestContext)
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

    @Dependency(\.portfolioAnalytics) var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selectionUnavailable:
                state.selectedWalletScopeFingerprint = nil
                state.activeRequestID = nil
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
                    return .merge(
                        .cancel(id: CancelID.cache),
                        .cancel(id: CancelID.history),
                        .cancel(id: CancelID.pnl))
                }
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.activeRequestID = nil
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
                state.activeRequestID = requestID
                state.historyStatus = .loading
                state.pnlStatus = .loading
                let pnlRange = state.pnlRange
                let cacheEffect = Effect<Action>.run { send in
                    do {
                        let cache = try await client.loadCache(
                            context.scope,
                            pnlRange,
                            context.currency)
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
                    return .none
                }
                let requestID = context.requestID(pnlRange: state.pnlRange)
                state.activeRequestID = requestID
                state.historyStatus = state.history.isEmpty ? .loading : .refreshing
                state.pnlStatus = state.pnl == nil ? .loading : .refreshing
                return refreshEffects(context: context, requestID: requestID, pnlRange: state.pnlRange)

            case let .clearCache(context):
                let requestID = context.requestID(pnlRange: state.pnlRange)
                state.activeRequestID = requestID
                return .run { send in
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
                state.history = []
                state.pnl = nil
                state.historyStatus = .idle
                state.pnlStatus = .idle
                return .merge(
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.history),
                    .cancel(id: CancelID.pnl))

            case let .pnlRangeChanged(range, context):
                state.pnlRange = range
                state.pnl = nil
                guard Self.isEligible(context, isAvailable: state.isAvailable) else {
                    state.pnlStatus = .idle
                    return .none
                }
                let requestID = context.requestID(pnlRange: range)
                state.activeRequestID = requestID
                state.pnlStatus = .loading
                return pnlEffect(context: context, requestID: requestID, pnlRange: range)

            case let .cacheLoaded(context, requestID, .success(cache)):
                guard requestID == state.activeRequestID else { return .none }
                state.history = cache.history
                state.historyStatus = .loaded
                state.pnl = cache.pnl

                let historyNeedsRefresh = cache.history.isEmpty
                    || cache.historyFetchedAt.map {
                        context.asOf.timeIntervalSince($0) >= ProviderPnLFreshness.freshTTL
                    } ?? true
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
                if pnlNeedsRefresh {
                    effects.append(pnlEffect(
                        context: context,
                        requestID: requestID,
                        pnlRange: state.pnlRange))
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
                state.historyStatus = .failed(error.failure)
                return .none

            case let .pnlResponse(requestID, .success(pnl)):
                guard requestID == state.activeRequestID else { return .none }
                state.pnl = pnl
                state.pnlStatus = .loaded
                return .none

            case let .pnlResponse(requestID, .failure(error)):
                guard requestID == state.activeRequestID else { return .none }
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

    private func refreshEffects(
        context: PortfolioAnalyticsRequestContext,
        requestID: String,
        pnlRange: ProviderPnLRange) -> Effect<Action> {
        .merge(
            historyEffect(context: context, requestID: requestID),
            pnlEffect(context: context, requestID: requestID, pnlRange: pnlRange))
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
