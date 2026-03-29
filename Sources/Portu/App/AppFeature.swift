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
}

extension SyncEngineClient: DependencyKey {
    static let liveValue = Self(
        sync: { fatalError("SyncEngineClient.liveValue must be overridden at Store creation") },
    )
    static let testValue = Self(
        sync: { SyncResult(failedAccounts: []) },
    )

    static func live(engine: SyncEngine) -> Self {
        Self(sync: { try await engine.sync() })
    }
}

extension DependencyValues {
    var syncEngine: SyncEngineClient {
        get { self[SyncEngineClient.self] }
        set { self[SyncEngineClient.self] = newValue }
    }
}

// MARK: - PriceServiceClient

struct PriceServiceClient {
    var fetchPrices: @Sendable ([String]) async throws -> PriceUpdate
}

extension PriceServiceClient: DependencyKey {
    static let liveValue = Self(
        fetchPrices: { _ in fatalError("PriceServiceClient.liveValue must be overridden at Store creation") },
    )
    static let testValue = Self(
        fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
    )

    static func live(service: PriceService) -> Self {
        Self(fetchPrices: { coinIds in
            try await service.fetchPriceUpdate(for: coinIds)
        })
    }
}

extension DependencyValues {
    var priceService: PriceServiceClient {
        get { self[PriceServiceClient.self] }
        set { self[PriceServiceClient.self] = newValue }
    }
}

// MARK: - AppFeature

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var selectedSection: SidebarSection = .overview
        var syncStatus: SyncStatus = .idle
        var connectionStatus: ConnectionStatus = .idle
        var prices: [String: Decimal] = [:]
        var priceChanges24h: [String: Decimal] = [:]
        var lastPriceUpdate: Date?
        var storeIsEphemeral: Bool = false
        var allAssets = AllAssetsFeature.State()
        var assetDetail = AssetDetailFeature.State()
        var accounts = AccountsFeature.State()
        var exposure = ExposureFeature.State()
        var performance = PerformanceFeature.State()
    }

    enum Action {
        case sectionSelected(SidebarSection)
        case syncTapped
        case syncProgressUpdated(Double)
        case syncCompleted(Result<SyncResult, Error>)
        case startPricePolling([String])
        case stopPricePolling
        case pricesReceived(PriceUpdate)
        case priceFetchFailed(Error)
        case allAssets(AllAssetsFeature.Action)
        case assetDetail(AssetDetailFeature.Action)
        case accounts(AccountsFeature.Action)
        case exposure(ExposureFeature.Action)
        case performance(PerformanceFeature.Action)
    }

    private enum CancelID {
        case pricePolling
    }

    @Dependency(\.syncEngine) var syncEngine
    @Dependency(\.priceService) var priceService
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

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
        Scope(state: \.exposure, action: \.exposure) {
            ExposureFeature()
        }
        Scope(state: \.performance, action: \.performance) {
            PerformanceFeature()
        }
        Reduce { state, action in
            switch action {
            case let .sectionSelected(section):
                state.selectedSection = section
                return .none

            case .syncTapped:
                guard state.syncStatus == .idle else { return .none }
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

            case let .startPricePolling(coinIds):
                state.connectionStatus = .fetching
                return .run { send in
                    while !Task.isCancelled {
                        do {
                            let update = try await priceService.fetchPrices(coinIds)
                            await send(.pricesReceived(update))
                        } catch {
                            await send(.priceFetchFailed(error))
                        }
                        try await clock.sleep(for: .seconds(30))
                    }
                }
                .cancellable(id: CancelID.pricePolling, cancelInFlight: true)

            case let .pricesReceived(update):
                state.prices.merge(update.prices) { _, new in new }
                state.priceChanges24h.merge(update.changes24h) { _, new in new }
                state.lastPriceUpdate = now
                state.connectionStatus = .idle
                return .none

            case let .priceFetchFailed(error):
                state.connectionStatus = .error(error.localizedDescription)
                return .none

            case .stopPricePolling:
                return .cancel(id: CancelID.pricePolling)

            case .allAssets:
                return .none

            case .assetDetail:
                return .none

            case .accounts:
                return .none

            case .exposure:
                return .none

            case .performance:
                return .none
            }
        }
    }
}

// MARK: - Equatable for Result

extension AppFeature.Action: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.sectionSelected(l), .sectionSelected(r)): l == r
        case (.syncTapped, .syncTapped): true
        case let (.syncProgressUpdated(l), .syncProgressUpdated(r)): l == r
        case let (.syncCompleted(.success(l)), .syncCompleted(.success(r))): l == r
        case (.syncCompleted(.failure), .syncCompleted(.failure)): true
        case let (.startPricePolling(l), .startPricePolling(r)): l == r
        case (.stopPricePolling, .stopPricePolling): true
        case let (.pricesReceived(l), .pricesReceived(r)): l == r
        case (.priceFetchFailed, .priceFetchFailed): true
        case let (.allAssets(l), .allAssets(r)): l == r
        case let (.assetDetail(l), .assetDetail(r)): l == r
        case let (.accounts(l), .accounts(r)): l == r
        case let (.exposure(l), .exposure(r)): l == r
        case let (.performance(l), .performance(r)): l == r
        default: false
        }
    }
}
