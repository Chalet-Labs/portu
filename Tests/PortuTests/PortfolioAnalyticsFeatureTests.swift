import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import Testing

@MainActor
// swiftlint:disable:next type_body_length
struct PortfolioAnalyticsFeatureTests {
    private let now = Date(timeIntervalSince1970: 1_704_153_600)

    @Test func `fresh cache renders immediately without PnL refresh`() async {
        let scope = makeScope()
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now.addingTimeInterval(-3600))
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let cachedHistory = [
            ProviderPortfolioValueDTO(
                timestamp: now,
                usdValue: 100,
                provider: .zerion,
                coverage: .providerReported)
        ]
        let calls = AnalyticsCallRecorder()
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                    PortfolioAnalyticsCache(
                        history: cachedHistory,
                        historyFetchedAt: now,
                        historyCoverageStartDate: ChartTimeRange.oneMonth.startDate(at: now),
                        pnl: cachedPnL)
                }
                $0.portfolioAnalytics.refreshHistory = { _, _ in
                    await calls.recordHistory()
                    return []
                }
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                    await calls.recordPnL()
                    return cachedPnL
                }
            }

        await store.send(.load(context)) {
            $0.loadRequestGeneration = 1
            $0.activeRequestID = "\(context.requestID(pnlRange: .oneMonth))|load|1"
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.history = cachedHistory
            $0.historyStatus = .loaded
            $0.pnlStatus = .loaded
            $0.pnl = cachedPnL
        }

        #expect(await calls.pnlCount == 0)
        #expect(await calls.historyCount == 0)
    }

    @Test func `fresh empty history cache does not refresh again`() async {
        let scope = makeScope()
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let calls = AnalyticsCallRecorder()
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                    PortfolioAnalyticsCache(
                        history: [],
                        historyFetchedAt: now,
                        historyCoverageStartDate: ChartTimeRange.oneMonth.startDate(at: now),
                        pnl: cachedPnL)
                }
                $0.portfolioAnalytics.refreshHistory = { _, _ in
                    await calls.recordHistory()
                    return []
                }
            }

        await store.send(.load(context)) {
            $0.loadRequestGeneration = 1
            $0.activeRequestID = "\(context.requestID(pnlRange: .oneMonth))|load|1"
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.historyStatus = .loaded
            $0.pnl = cachedPnL
            $0.pnlStatus = .loaded
        }

        #expect(await calls.historyCount == 0)
    }

    @Test func `stale cache remains visible while PnL refreshes`() async {
        let scope = makeScope()
        let stale = ProviderPnLDTO(
            range: .oneMonth,
            currency: .chf,
            totalGain: 10,
            fetchedAt: now.addingTimeInterval(-ProviderPnLFreshness.freshTTL))
        let refreshed = ProviderPnLDTO(
            range: .oneMonth,
            currency: .chf,
            totalGain: 20,
            fetchedAt: now)
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .chf,
            implementations: [],
            asOf: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                pnlRange: .oneMonth)) {
            PortfolioAnalyticsFeature()
        } withDependencies: {
            $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                PortfolioAnalyticsCache(
                    history: [],
                    historyFetchedAt: now,
                    pnl: stale)
            }
            $0.portfolioAnalytics.refreshHistory = { _, _ in [] }
            $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in refreshed }
        }

        await store.send(.load(context)) {
            $0.loadRequestGeneration = 1
            $0.activeRequestID = "\(context.requestID(pnlRange: .oneMonth))|load|1"
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.receive(\.cacheLoaded) {
            $0.activeHistoryRequestID =
                "\(context.requestID(pnlRange: .oneMonth))|load|1"
            $0.activePnLRequestID =
                "\(context.requestID(pnlRange: .oneMonth))|load|1"
            $0.historyStatus = .loading
            $0.pnlStatus = .refreshing
            $0.pnl = stale
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
        }
        await store.receive(\.historyResponse) {
            $0.activeHistoryRequestID = nil
            $0.historyStatus = .loaded
        }
        await store.receive(\.pnlResponse) {
            $0.activePnLRequestID = nil
            $0.pnlRefreshAttemptID = nil
            $0.pnlStatus = .loaded
            $0.pnl = refreshed
        }
    }

    @Test(arguments: [DataSource.exchange, .manual, .zapper])
    func `unsupported account sources never call analytics`(_ dataSource: DataSource) async {
        let calls = AnalyticsCallRecorder()
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(dataSource: dataSource),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                    await calls.recordCache()
                    return .empty
                }
            }

        await store.send(.load(context))

        #expect(await calls.cacheCount == 0)
    }

    @Test func `analytics feature gate is off by default and has explicit opt ins`() throws {
        let suiteName = "PortfolioAnalyticsFeatureTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(PortfolioAnalyticsFeatureFlag.isEnabled(
            environment: [:],
            defaults: defaults) == false)
        #expect(PortfolioAnalyticsFeatureFlag.isEnabled(
            environment: ["PORTU_ZERION_ANALYTICS": "1"],
            defaults: defaults))

        defaults.set(true, forKey: PortfolioAnalyticsFeatureFlag.defaultsKey)
        #expect(PortfolioAnalyticsFeatureFlag.isEnabled(
            environment: [:],
            defaults: defaults))
    }

    @Test func `inactive transition preserves cached read only analytics`() async {
        let scope = makeScope()
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now,
            isAccountActive: false)
        let calls = AnalyticsCallRecorder()
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                history: [.init(
                    timestamp: now,
                    usdValue: 100,
                    provider: .zerion,
                    coverage: .providerReported)],
                pnl: cachedPnL,
                historyStatus: .loaded,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        } withDependencies: {
            $0.portfolioAnalytics.loadCache = { _, _, _, _ in
                await calls.recordCache()
                return .empty
            }
        }

        await store.send(.load(context))

        #expect(store.state.pnl == cachedPnL)
        #expect(store.state.history.count == 1)
        #expect(await calls.cacheCount == 0)
    }

    @Test func `unavailable selection clears analytics from the previous wallet`() async {
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                selectedWalletScopeFingerprint: "old-wallet",
                activeRequestID: "old-request",
                history: [.init(
                    timestamp: now,
                    usdValue: 100,
                    provider: .zerion,
                    coverage: .providerReported)],
                pnl: cachedPnL,
                historyStatus: .loaded,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.selectionUnavailable) {
            $0.selectedWalletScopeFingerprint = nil
            $0.activeRequestID = nil
            $0.history = []
            $0.pnl = nil
            $0.historyStatus = .idle
            $0.pnlStatus = .idle
        }
    }

    @Test func `wallet scope selection clears previous wallet before loading fallback`() async {
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                selectedWalletScopeFingerprint: "old-wallet",
                activeRequestID: "old-request",
                history: [.init(
                    timestamp: now,
                    usdValue: 100,
                    provider: .zerion,
                    coverage: .providerReported)],
                pnl: cachedPnL,
                historyStatus: .loaded,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.walletScopeSelected("new-wallet")) {
            $0.selectedWalletScopeFingerprint = "new-wallet"
            $0.activeRequestID = nil
            $0.history = []
            $0.pnl = nil
            $0.historyStatus = .idle
            $0.pnlStatus = .idle
        }
    }

    @Test func `typed Zerion failures retain actionable state and cached data`() async {
        let scope = makeScope()
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now.addingTimeInterval(-ProviderPnLFreshness.freshTTL))
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                pnl: cachedPnL,
                historyStatus: .loaded,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        } withDependencies: {
            $0.portfolioAnalytics.refreshHistory = { _, _ in [] }
            $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in
                throw ZerionError.paymentRequired
            }
        }

        await store.send(.refresh(context)) {
            $0.refreshRequestGeneration = 1
            $0.activeRequestID = "\(context.requestID(pnlRange: .oneMonth))|refresh|1"
            $0.activeHistoryRequestID =
                "\(context.requestID(pnlRange: .oneMonth))|refresh|1"
            $0.activePnLRequestID =
                "\(context.requestID(pnlRange: .oneMonth))|refresh|1"
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
            $0.historyStatus = .loading
            $0.pnlStatus = .refreshing
        }
        await store.receive(\.historyResponse) {
            $0.activeHistoryRequestID = nil
            $0.history = []
            $0.historyStatus = .loaded
        }
        await store.receive(\.pnlResponse) {
            $0.activePnLRequestID = nil
            $0.pnlStatus = .failed(.planUnavailable)
        }
        #expect(store.state.pnl == cachedPnL)
    }

    @Test func `cancellation is not surfaced as a failure`() async {
        let context = PortfolioAnalyticsRequestContext(
            scope: makeScope(),
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(isAvailable: true)) {
                PortfolioAnalyticsFeature()
            } withDependencies: {
                $0.portfolioAnalytics.refreshHistory = { _, _ in throw CancellationError() }
                $0.portfolioAnalytics.refreshPnL = { _, _, _, _, _ in throw CancellationError() }
            }

        await store.send(.refresh(context)) {
            $0.refreshRequestGeneration = 1
            $0.activeRequestID = "\(context.requestID(pnlRange: .oneMonth))|refresh|1"
            $0.activeHistoryRequestID =
                "\(context.requestID(pnlRange: .oneMonth))|refresh|1"
            $0.activePnLRequestID =
                "\(context.requestID(pnlRange: .oneMonth))|refresh|1"
            $0.pnlRefreshAttemptID = context.pnlRequestID(pnlRange: .oneMonth)
            $0.historyStatus = .loading
            $0.pnlStatus = .loading
        }
        await store.finish()
    }

    @Test func `late response cannot overwrite the active wallet scope`() async {
        let cachedPnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: now)
        let obsoletePnL = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 999,
            fetchedAt: now)
        let store = TestStore(
            initialState: PortfolioAnalyticsFeature.State(
                isAvailable: true,
                activeRequestID: "current",
                pnl: cachedPnL,
                pnlStatus: .loaded)) {
            PortfolioAnalyticsFeature()
        }

        await store.send(.pnlResponse("obsolete", .success(obsoletePnL)))

        #expect(store.state.pnl == cachedPnL)
        #expect(store.state.activeRequestID == "current")
    }

    @Test(arguments: [
        (ZerionError.temporarilyUnavailable(retryAfter: 7), PortfolioAnalyticsFailure.preparing(retryAfter: 7)),
        (.paymentRequired, .planUnavailable),
        (.unauthorized, .invalidCredential),
        (.badRequest, .invalidRequest),
        (.notFound, .unavailableForScope),
        (
            .rateLimited(
                remainingSecond: 0,
                remainingDay: 10,
                remainingMonth: 100,
                reset: "3"),
            .rateLimited),
        (.unsupportedAnalyticsScope, .unsupportedAggregation)
    ])
    func `client maps Zerion failures to typed UI outcomes`(
        error: ZerionError,
        expected: PortfolioAnalyticsFailure) {
        #expect(PortfolioAnalyticsClientError(error).failure == expected)
    }

    private func makeScope(dataSource: DataSource = .zerion) -> PortfolioAnalyticsScope {
        PortfolioAnalyticsScope(
            accountID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            dataSource: dataSource,
            addresses: [.init(
                family: .evm,
                value: "0x1111111111111111111111111111111111111111")])
    }
}

private actor AnalyticsCallRecorder {
    private(set) var cacheCount = 0
    private(set) var historyCount = 0
    private(set) var pnlCount = 0

    func recordCache() {
        cacheCount += 1
    }

    func recordHistory() {
        historyCount += 1
    }

    func recordPnL() {
        pnlCount += 1
    }
}
