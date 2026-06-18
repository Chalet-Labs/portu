import ComposableArchitecture
import Foundation
import PortuCore
import PortuNetwork

// MARK: - AppFeature

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var selectedSection: SidebarSection = .overview
        var isSettingsPresented = false
        var detailRoute: AppDetailRoute {
            isSettingsPresented ? .settings : .section(selectedSection)
        }

        var sidebarSelection: SidebarSection? {
            isSettingsPresented ? nil : selectedSection
        }

        var syncStatus: SyncStatus = .idle
        var connectionStatus: ConnectionStatus = .idle
        var prices: [String: Decimal] = [:]
        var priceChanges24h: [String: Decimal] = [:]
        var lastPriceUpdate: Date?
        var storeIsEphemeral: Bool = false
        var allAssets = AllAssetsFeature.State()
        var assetDetail = AssetDetailFeature.State()
        var accounts = AccountsFeature.State()
        var performance = PerformanceFeature.State()
        var portfolioHealth = PortfolioHealthFeature.State()
        var historicalPriceBackfill = HistoricalPriceBackfillFeature.State()
    }

    enum Action {
        case sectionSelected(SidebarSection)
        case settingsSelected
        case syncTapped
        case syncProgressUpdated(Double)
        case syncCompleted(Result<SyncResult, Error>)
        case startScheduledSync
        case stopScheduledSync
        case scheduledSyncDue(PortfolioSyncScope)
        case scheduledSyncCompleted(Result<SyncResult, Error>)
        case startPricePolling([String])
        case stopPricePolling
        case pricesReceived(PriceUpdate)
        case priceFetchFailed(Error)
        case allAssets(AllAssetsFeature.Action)
        case assetDetail(AssetDetailFeature.Action)
        case accounts(AccountsFeature.Action)
        case performance(PerformanceFeature.Action)
        case portfolioHealth(PortfolioHealthFeature.Action)
        case historicalPriceBackfill(HistoricalPriceBackfillFeature.Action)
    }

    private enum CancelID {
        case pricePolling
        case scheduledSync
    }

    @Dependency(\.syncEngine) var syncEngine
    @Dependency(\.priceService) var priceService
    @Dependency(\.pricePollingSettings) var pricePollingSettings
    @Dependency(\.providerSyncSettings) var providerSyncSettings
    @Dependency(\.continuousClock) var clock
    @Dependency(\.currentDate) var currentDate

    var body: some ReducerOf<Self> {
        Scope(state: \.allAssets, action: \.allAssets) {
            AllAssetsFeature()
        }
        Scope(state: \.assetDetail, action: \.assetDetail) {
            AssetDetailFeature()
        }
        Scope(state: \.accounts, action: \.accounts) {
            AccountsFeature()
        }
        Scope(state: \.performance, action: \.performance) {
            PerformanceFeature()
        }
        Scope(state: \.portfolioHealth, action: \.portfolioHealth) {
            PortfolioHealthFeature()
        }
        Scope(state: \.historicalPriceBackfill, action: \.historicalPriceBackfill) {
            HistoricalPriceBackfillFeature()
        }
        Reduce { state, action in
            switch action {
            case let .sectionSelected(section):
                state.selectedSection = section
                state.isSettingsPresented = false
                return .none

            case .settingsSelected:
                state.isSettingsPresented = true
                return .none

            case .syncTapped:
                if case .syncing = state.syncStatus { return .none }
                state.syncStatus = .syncing(progress: 0)
                return .run { send in
                    let result = try await syncEngine.sync()
                    await send(.syncCompleted(.success(result)))
                } catch: { error, send in
                    await send(.syncCompleted(.failure(error)))
                }

            case let .syncProgressUpdated(progress):
                state.syncStatus = .syncing(progress: progress)
                return .none

            case let .syncCompleted(.success(result)):
                if result.isPartial {
                    state.syncStatus = .completedWithErrors(failedAccounts: result.failedAccounts)
                } else {
                    state.syncStatus = .idle
                }
                return .none

            case let .syncCompleted(.failure(error)):
                state.syncStatus = .error(error.localizedDescription)
                return .none

            case .startScheduledSync:
                var effects: [Effect<Action>] = []
                if let zapperInterval = providerSyncSettings.zapperPortfolioSyncInterval() {
                    effects.append(.run { send in
                        while !Task.isCancelled {
                            try await clock.sleep(for: zapperInterval)
                            await send(.scheduledSyncDue(.zapper))
                        }
                    })
                }
                if let exchangeInterval = providerSyncSettings.exchangePortfolioSyncInterval() {
                    effects.append(.run { send in
                        while !Task.isCancelled {
                            try await clock.sleep(for: exchangeInterval)
                            await send(.scheduledSyncDue(.exchange))
                        }
                    })
                }
                guard effects.isEmpty == false else { return .none }
                return .merge(effects)
                    .cancellable(id: CancelID.scheduledSync, cancelInFlight: true)

            case .stopScheduledSync:
                return .cancel(id: CancelID.scheduledSync)

            case let .scheduledSyncDue(scope):
                if case .syncing = state.syncStatus { return .none }
                state.syncStatus = .syncing(progress: 0)
                return .run { send in
                    let result = try await syncEngine.syncScope(scope)
                    await send(.scheduledSyncCompleted(.success(result)))
                } catch: { error, send in
                    await send(.scheduledSyncCompleted(.failure(error)))
                }

            case let .scheduledSyncCompleted(.success(result)):
                if result.isPartial {
                    state.syncStatus = .completedWithErrors(failedAccounts: result.failedAccounts)
                } else {
                    state.syncStatus = .idle
                }
                return .none

            case let .scheduledSyncCompleted(.failure(error)):
                state.syncStatus = .error(error.localizedDescription)
                return .none

            case let .startPricePolling(coinIds):
                let request = PricePollingIDResolver.split(coinIds)
                guard request.isEmpty == false else { return .none }
                state.connectionStatus = .fetching

                var effects: [Effect<Action>] = [
                    .run { send in
                        while !Task.isCancelled {
                            do {
                                let update = try await priceService.fetchCoinGeckoPrices(request)
                                await send(.pricesReceived(update))
                            } catch {
                                await send(.priceFetchFailed(error))
                            }
                            try await clock.sleep(for: pricePollingSettings.refreshInterval())
                        }
                    }
                ]

                if
                    request.zapperIdentities.isEmpty == false,
                    let zapperFallbackInterval = pricePollingSettings.zapperFallbackInterval() {
                    effects.append(.run { send in
                        while !Task.isCancelled {
                            do {
                                let update = try await priceService.fetchZapperPrices(request.zapperIdentities)
                                await send(.pricesReceived(update))
                            } catch {
                                await send(.priceFetchFailed(error))
                            }
                            try await clock.sleep(for: zapperFallbackInterval)
                        }
                    })
                }

                return .merge(effects)
                    .cancellable(id: CancelID.pricePolling, cancelInFlight: true)

            case let .pricesReceived(update):
                state.prices.merge(update.prices) { _, new in new }
                state.priceChanges24h.merge(update.changes24h) { _, new in new }
                state.lastPriceUpdate = currentDate.now()
                state.connectionStatus = .idle
                return .none

            case let .priceFetchFailed(error):
                state.connectionStatus = .error(error.localizedDescription)
                return .none

            case .stopPricePolling:
                state.connectionStatus = .idle
                return .cancel(id: CancelID.pricePolling)

            case .allAssets:
                return .none

            case .assetDetail:
                return .none

            case .accounts:
                return .none

            case .performance:
                return .none

            case .portfolioHealth:
                return .none

            case .historicalPriceBackfill:
                return .none
            }
        }
    }
}

// MARK: - Equatable for Result

extension AppFeature.Action: Equatable {
    // swiftlint:disable:next cyclomatic_complexity
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.sectionSelected(l), .sectionSelected(r)): l == r
        case (.settingsSelected, .settingsSelected): true
        case (.syncTapped, .syncTapped): true
        case let (.syncProgressUpdated(l), .syncProgressUpdated(r)): l == r
        case let (.syncCompleted(.success(l)), .syncCompleted(.success(r))): l == r
        case (.syncCompleted(.failure), .syncCompleted(.failure)): true
        case (.startScheduledSync, .startScheduledSync): true
        case (.stopScheduledSync, .stopScheduledSync): true
        case let (.scheduledSyncDue(l), .scheduledSyncDue(r)): l == r
        case let (.scheduledSyncCompleted(.success(l)), .scheduledSyncCompleted(.success(r))): l == r
        case (.scheduledSyncCompleted(.failure), .scheduledSyncCompleted(.failure)): true
        case let (.startPricePolling(l), .startPricePolling(r)): l == r
        case (.stopPricePolling, .stopPricePolling): true
        case let (.pricesReceived(l), .pricesReceived(r)): l == r
        case (.priceFetchFailed, .priceFetchFailed): true
        case let (.allAssets(l), .allAssets(r)): l == r
        case let (.assetDetail(l), .assetDetail(r)): l == r
        case let (.accounts(l), .accounts(r)): l == r
        case let (.performance(l), .performance(r)): l == r
        case let (.portfolioHealth(l), .portfolioHealth(r)): l == r
        case let (.historicalPriceBackfill(l), .historicalPriceBackfill(r)): l == r
        default: false
        }
    }
}
