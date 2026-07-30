// swiftlint:disable file_length

import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import Testing

@MainActor
// swiftlint:disable:next type_body_length
struct PortfolioAnalyticsReviewTests {
    private let now = Date(timeIntervalSince1970: 1_704_153_600)

    @Test func `fresh short history refreshes when a longer chart range is requested`() async {
        let scope = makeScope()
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneYear,
            currency: .usd,
            implementations: [],
            asOf: now)
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let calls = ReviewAnalyticsCallRecorder()
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                    PortfolioAnalyticsCache(
                        history: [.init(
                            timestamp: now.addingTimeInterval(-7 * 86400),
                            usdValue: 100,
                            provider: .zerion,
                            coverage: .providerReported)],
                        historyFetchedAt: now,
                        historyCoverageStartDate: now.addingTimeInterval(-7 * 86400),
                        pnl: cachedPnL)
                }
                $0.portfolioAnalytics.refreshHistory = { _, _ in
                    await calls.recordHistory()
                    return []
                }
            }

        await store.send(.load(context)) {
            $0.activeRequestID = context.requestID(pnlRange: .oneMonth)
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.history = [.init(
                timestamp: now.addingTimeInterval(-7 * 86400),
                usdValue: 100,
                provider: .zerion,
                coverage: .providerReported)]
            $0.historyStatus = .refreshing
            $0.pnl = cachedPnL
            $0.pnlStatus = .loaded
        }
        await store.receive(\.historyResponse) {
            $0.history = []
            $0.historyStatus = .loaded
        }
        #expect(await calls.historyCount == 1)
    }

    @Test func `pnl range change loads matching cache before refreshing`() async {
        let scope = makeScope()
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let cached = ProviderPnLDTO(
            range: .oneYear,
            currency: .usd,
            totalGain: 20,
            fetchedAt: now)
        let calls = ReviewAnalyticsCallRecorder()
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                pnl: .init(
                    range: .oneMonth,
                    currency: .usd,
                    totalGain: 10,
                    fetchedAt: now),
                historyStatus: .loaded,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        } withDependencies: {
            $0.portfolioAnalytics.loadCache = { _, range, _, _ in
                await calls.recordCache()
                #expect(range == .oneYear)
                return PortfolioAnalyticsCache(
                    history: [],
                    historyFetchedAt: now,
                    historyCoverageStartDate: ChartTimeRange.oneMonth.startDate(at: now),
                    pnl: cached)
            }
            $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                await calls.recordPnL()
                return cached
            }
        }

        await store.send(.pnlRangeChanged(.oneYear, context)) {
            $0.pnlRange = .oneYear
            $0.activeRequestID = nil
            $0.pnl = nil
            $0.pnlStatus = .idle
        }
        await store.receive(\.load) {
            $0.activeRequestID = context.requestID(pnlRange: .oneYear)
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.historyStatus = .loading
            $0.pnl = cached
            $0.pnlStatus = .loaded
        }
        await store.receive(\.historyResponse) {
            $0.historyStatus = .loaded
        }
        #expect(await calls.cacheCount == 1)
        #expect(await calls.pnlCount == 0)
    }

    @Test func `loading a different request clears stale pnl`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .chf,
            implementations: [],
            asOf: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                activeRequestID: "previous-account-or-currency",
                pnl: .init(
                    range: .oneMonth,
                    currency: .usd,
                    totalGain: 10,
                    fetchedAt: now),
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        } withDependencies: {
            $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                try await Task.sleep(for: .seconds(3600))
                return .empty
            }
        }

        await store.send(.load(context)) {
            $0.activeRequestID = context.requestID(pnlRange: .oneMonth)
            $0.pnl = nil
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.send(.selectionUnavailable) {
            $0.activeRequestID = nil
            $0.historyStatus = .idle
            $0.pnlStatus = .idle
        }
        await store.finish()
    }

    @Test func `chart range changes do not repeat a stale pnl refresh`() async {
        let shortContext = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneWeek,
            currency: .usd,
            implementations: [],
            asOf: now)
        let longContext = PortfolioAnalyticsRequestContext(
            scope: shortContext.scope,
            chartRange: .oneYear,
            currency: shortContext.currency,
            implementations: shortContext.implementations,
            asOf: shortContext.asOf)
        let stalePnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now.addingTimeInterval(-86400))
        let calls = ReviewAnalyticsCallRecorder()
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                    PortfolioAnalyticsCache(
                        history: [.init(
                            timestamp: now,
                            usdValue: 100,
                            provider: .zerion,
                            coverage: .providerReported)],
                        historyFetchedAt: now,
                        historyCoverageStartDate: ChartTimeRange.oneYear.startDate(at: now),
                        pnl: stalePnL)
                }
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                    await calls.recordPnL()
                    throw ZerionError.paymentRequired
                }
            }

        await store.send(.load(shortContext)) {
            $0.activeRequestID = shortContext.requestID(pnlRange: .oneMonth)
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.history = [.init(
                timestamp: now,
                usdValue: 100,
                provider: .zerion,
                coverage: .providerReported)]
            $0.historyStatus = .loaded
            $0.pnl = stalePnL
            $0.pnlStatus = .refreshing
            $0.pnlRefreshAttemptID = shortContext.pnlRequestID(pnlRange: .oneMonth)
        }
        await store.receive(\.pnlResponse) {
            $0.pnlStatus = .failed(.planUnavailable)
        }

        await store.send(.load(longContext)) {
            $0.activeRequestID = longContext.requestID(pnlRange: .oneMonth)
            $0.pnl = nil
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.historyStatus = .loaded
            $0.pnl = stalePnL
            $0.pnlStatus = .loaded
        }

        #expect(await calls.pnlCount == 1)
    }

    @Test func `feature exit resets the pnl refresh attempt scope`() async {
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                pnlRefreshAttemptID: "attempt",
                historyStatus: .loaded,
                pnlStatus: .failed(.planUnavailable))) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.featureExited) {
            $0.pnlRefreshAttemptID = nil
        }
    }

    @Test func `inactive transition clears loading indicators`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now,
            isAccountActive: false)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                activeRequestID: "old",
                historyStatus: .refreshing,
                pnlStatus: .loading)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.load(context)) {
            $0.activeRequestID = nil
            $0.historyStatus = .idle
            $0.pnlStatus = .idle
        }
    }

    @Test func `inactive refresh clears loading indicators`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now,
            isAccountActive: false)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                activeRequestID: "old",
                historyStatus: .loading,
                pnlStatus: .refreshing)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.refresh(context)) {
            $0.activeRequestID = nil
            $0.historyStatus = .idle
            $0.pnlStatus = .idle
        }
    }

    @Test func `clear cache cancels analytics refreshes before deleting rows`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let requestID = context.requestID(pnlRange: .oneMonth)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.refreshHistory = { _, _ in
                    try await Task.sleep(for: .seconds(3600))
                    return []
                }
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                    try await Task.sleep(for: .seconds(3600))
                    return ProviderPnLDTO(
                        range: .oneMonth,
                        currency: .usd,
                        totalGain: 0,
                        fetchedAt: now)
                }
                $0.portfolioAnalytics.clearAccountCache = { _ in 2 }
            }

        await store.send(.refresh(context)) {
            $0.activeRequestID = requestID
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.send(.clearCache(context)) {
            $0.pnlRefreshAttemptID = nil
        }
        await store.receive(\.clearCacheResponse) {
            $0.historyStatus = .idle
            $0.pnlStatus = .idle
        }
        await store.finish()
    }

    @Test func `inactive pnl range change preserves cached read only analytics`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let inactiveContext = PortfolioAnalyticsRequestContext(
            scope: context.scope,
            chartRange: context.chartRange,
            currency: context.currency,
            implementations: context.implementations,
            asOf: context.asOf,
            isAccountActive: false)
        let cached = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                pnl: cached,
                historyStatus: .loaded,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.pnlRangeChanged(.oneYear, inactiveContext))
        #expect(store.state.pnlRange == .oneMonth)
        #expect(store.state.pnl == cached)
        #expect(store.state.pnlStatus == .loaded)
    }

    @Test func `custom chart range does not request provider history`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .custom,
            currency: .usd,
            implementations: [],
            asOf: now)
        let calls = ReviewAnalyticsCallRecorder()
        let pnl = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.refreshHistory = { _, _ in
                    await calls.recordHistory()
                    return []
                }
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                    await calls.recordPnL()
                    return pnl
                }
            }

        await store.send(.refresh(context)) {
            $0.activeRequestID = context.requestID(pnlRange: .oneMonth)
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
            $0.pnlStatus = .loading
        }
        await store.receive(\.pnlResponse) {
            $0.pnlRefreshAttemptID = nil
            $0.pnl = pnl
            $0.pnlStatus = .loaded
        }
        #expect(await calls.historyCount == 0)
        #expect(await calls.pnlCount == 1)
    }

    @Test func `pnl control refresh does not request provider history`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let calls = ReviewAnalyticsCallRecorder()
        let pnl = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.date.now = now
                $0.portfolioAnalytics.refreshHistory = { _, _ in
                    await calls.recordHistory()
                    return []
                }
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                    await calls.recordPnL()
                    return pnl
                }
            }

        await store.send(.refreshPnL(context)) {
            $0.activeRequestID = context.requestID(pnlRange: .oneMonth)
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
            $0.pnlStatus = .loading
        }
        await store.receive(\.pnlResponse) {
            $0.pnlRefreshAttemptID = nil
            $0.pnl = pnl
            $0.pnlStatus = .loaded
        }
        #expect(await calls.historyCount == 0)
        #expect(await calls.pnlCount == 1)
    }

    @Test func `pnl control refresh stamps the request at action handling time`() async {
        let clickTime = now.addingTimeInterval(3600)
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let calls = ReviewAnalyticsCallRecorder()
        let pnl = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: clickTime)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.date.now = clickTime
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, asOf in
                    await calls.recordPnL(asOf: asOf)
                    return pnl
                }
            }

        await store.send(.refreshPnL(context)) {
            $0.activeRequestID = context.requestID(pnlRange: .oneMonth)
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
            $0.pnlStatus = .loading
        }
        await store.receive(\.pnlResponse) {
            $0.pnlRefreshAttemptID = nil
            $0.pnl = pnl
            $0.pnlStatus = .loaded
        }
        #expect(await calls.lastPnLAsOf == clickTime)
    }

    @Test func `combined scope not found automatically selects its individual fallback`() async {
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                activeRequestID: "combined",
                fallbackScopeFingerprint: "individual",
                historyStatus: .loading,
                pnlStatus: .loading)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.pnlResponse(
            "combined",
            .failure(PortfolioAnalyticsClientError(ZerionError.notFound)))) {
                $0.selectedWalletScopeFingerprint = "individual"
                $0.activeRequestID = nil
                $0.fallbackScopeFingerprint = nil
                $0.historyStatus = .idle
                $0.pnlStatus = .idle
            }
    }

    private func makeScope() -> PortfolioAnalyticsScope {
        PortfolioAnalyticsScope(
            accountID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            dataSource: .zerion,
            addresses: [.init(
                family: .evm,
                value: "0x1111111111111111111111111111111111111111")])
    }
}

private actor ReviewAnalyticsCallRecorder {
    private(set) var cacheCount = 0
    private(set) var historyCount = 0
    private(set) var pnlCount = 0
    private(set) var lastPnLAsOf: Date?

    func recordCache() {
        cacheCount += 1
    }

    func recordHistory() {
        historyCount += 1
    }

    func recordPnL() {
        pnlCount += 1
    }

    func recordPnL(asOf: Date) {
        pnlCount += 1
        lastPnLAsOf = asOf
    }
}
