// swiftlint:disable file_length

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
        var syncingAccountID: UUID?
        var connectionStatus: ConnectionStatus = .idle
        var selectedCurrency: FiatCurrency = .default
        // Set while a non-USD switch waits for its FX rate; the switch is committed
        // to `selectedCurrency` only once the rate arrives, so views never format
        // cached USD values under the new currency's label.
        var pendingCurrency: FiatCurrency?
        var currentUSDToDisplayRate: Decimal = 1
        var historicalFXAvailability: CurrencyFXAvailability = .available
        var prices: [String: Decimal] = [:]
        var priceChanges24h: [String: Decimal] = [:]
        var lastPriceUpdate: Date?
        var pricePollingIDs: [String] = []
        var storeIsEphemeral: Bool = false
        var allAssets = AllAssetsFeature.State()
        var assetDetail = AssetDetailFeature.State()
        var accounts = AccountsFeature.State()
        var performance = PerformanceFeature.State()
        var portfolioHealth = PortfolioHealthFeature.State()
        var historicalPriceBackfill = HistoricalPriceBackfillFeature.State()
    }

    enum Action {
        case appLaunched
        case sectionSelected(SidebarSection)
        case settingsSelected
        case syncTapped
        case accountSyncTapped(UUID)
        case syncProgressUpdated(Double)
        case syncCompleted(Result<SyncResult, Error>)
        case accountSyncCompleted(Result<SyncResult, Error>)
        case startScheduledSync
        case stopScheduledSync
        case scheduledSyncDue(PortfolioSyncScope)
        case scheduledSyncCompleted(Result<SyncResult, Error>)
        case displayCurrencySelected(FiatCurrency)
        case currentCurrencyConversionRateReceived(FiatCurrency, Result<Decimal, CurrencyConversionRefreshError>)
        case currencyConversionRefreshCompleted(FiatCurrency, Result<CurrencyConversionRefreshResult, CurrencyConversionRefreshError>)
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
        case currencyConversion
    }

    @Dependency(\.syncEngine) var syncEngine
    @Dependency(\.priceService) var priceService
    @Dependency(\.currencyConversion) var currencyConversion
    @Dependency(\.displayCurrencyPreference) var displayCurrencyPreference
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
            case .appLaunched:
                // A saved non-USD currency is restored into initial state without an
                // FX refresh, so displayed values would stay raw USD until the user
                // toggled currencies. Kick off the conversion refresh on launch.
                guard state.selectedCurrency != .usd else { return .none }
                state.historicalFXAvailability = .loading
                return currencyConversionEffect(currency: state.selectedCurrency)

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
                state.syncingAccountID = nil
                return .run { send in
                    let result = try await syncEngine.sync()
                    await send(.syncCompleted(.success(result)))
                } catch: { error, send in
                    await send(.syncCompleted(.failure(error)))
                }

            case let .accountSyncTapped(accountID):
                if case .syncing = state.syncStatus { return .none }
                state.syncStatus = .syncing(progress: 0)
                state.syncingAccountID = accountID
                return .run { send in
                    let result = try await syncEngine.syncAccount(accountID)
                    await send(.accountSyncCompleted(.success(result)))
                } catch: { error, send in
                    await send(.accountSyncCompleted(.failure(error)))
                }

            case let .syncProgressUpdated(progress):
                state.syncStatus = .syncing(progress: progress)
                return .none

            case let .syncCompleted(.success(result)):
                state.syncingAccountID = nil
                if result.isPartial {
                    state.syncStatus = .completedWithErrors(failedAccounts: result.failedAccounts)
                } else {
                    state.syncStatus = .idle
                }
                return .none

            case let .syncCompleted(.failure(error)):
                state.syncingAccountID = nil
                state.syncStatus = .error(error.localizedDescription)
                return .none

            case let .accountSyncCompleted(.success(result)):
                state.syncingAccountID = nil
                if result.isPartial {
                    state.syncStatus = .completedWithErrors(failedAccounts: result.failedAccounts)
                } else {
                    state.syncStatus = .idle
                }
                return .none

            case let .accountSyncCompleted(.failure(error)):
                // A single-account failure is surfaced on that row's `lastSyncError`
                // when the engine throws allAccountsFailed after persisting the row
                // error. Later-stage failures (snapshot/save) have no row error to
                // show, so surface those globally.
                state.syncingAccountID = nil
                if (error as? SyncError) == .allAccountsFailed {
                    state.syncStatus = .idle
                } else {
                    state.syncStatus = .error(error.localizedDescription)
                }
                return .none

            case .startScheduledSync:
                return .run { send in
                    var lastZapperSync = currentDate.now()
                    var lastExchangeSync = currentDate.now()

                    while !Task.isCancelled {
                        let now = currentDate.now()
                        let zapperInterval = providerSyncSettings.zapperPortfolioSyncInterval()
                        let exchangeInterval = providerSyncSettings.exchangePortfolioSyncInterval()

                        if let zapperInterval {
                            if now.timeIntervalSince(lastZapperSync) >= Self.timeInterval(for: zapperInterval) {
                                lastZapperSync = now
                                await send(.scheduledSyncDue(.zapper))
                            }
                        } else {
                            lastZapperSync = now
                        }

                        if let exchangeInterval {
                            if now.timeIntervalSince(lastExchangeSync) >= Self.timeInterval(for: exchangeInterval) {
                                lastExchangeSync = now
                                await send(.scheduledSyncDue(.exchange))
                            }
                        } else {
                            lastExchangeSync = now
                        }

                        let sleepDuration = Self.scheduledSyncSleepDuration(
                            now: now,
                            lastZapperSync: lastZapperSync,
                            lastExchangeSync: lastExchangeSync,
                            zapperInterval: zapperInterval,
                            exchangeInterval: exchangeInterval)
                        try await clock.sleep(for: sleepDuration)
                    }
                }
                .cancellable(id: CancelID.scheduledSync, cancelInFlight: true)

            case .stopScheduledSync:
                return .cancel(id: CancelID.scheduledSync)

            case let .scheduledSyncDue(scope):
                if case .syncing = state.syncStatus { return .none }
                state.syncStatus = .syncing(progress: 0)
                state.syncingAccountID = nil
                return .run { send in
                    let result = try await syncEngine.syncScope(scope)
                    await send(.scheduledSyncCompleted(.success(result)))
                } catch: { error, send in
                    await send(.scheduledSyncCompleted(.failure(error)))
                }

            case let .scheduledSyncCompleted(.success(result)):
                state.syncingAccountID = nil
                if result.isPartial {
                    state.syncStatus = .completedWithErrors(failedAccounts: result.failedAccounts)
                } else {
                    state.syncStatus = .idle
                }
                return .none

            case let .scheduledSyncCompleted(.failure(error)):
                state.syncingAccountID = nil
                state.syncStatus = .error(error.localizedDescription)
                return .none

            case let .displayCurrencySelected(currency):
                // Dedupe against the effective target: while a non-USD switch is in
                // flight, `pendingCurrency` is where the user is already heading.
                let activeTarget = state.pendingCurrency ?? state.selectedCurrency
                guard currency != activeTarget else { return .none }

                if currency == .usd {
                    // USD needs no FX rate, so the switch is always safe to commit now.
                    state.pendingCurrency = nil
                    return commitDisplayCurrency(&state, currency: .usd, rate: 1)
                }

                // Non-USD: defer the switch until the current rate is known. Committing
                // eagerly resets the rate to 1 while relabeling values, so cached USD
                // totals would show unchanged under the new currency until a retry.
                state.pendingCurrency = currency
                state.historicalFXAvailability = .loading
                return currencyConversionEffect(currency: currency)

            case let .currentCurrencyConversionRateReceived(currency, .success(rate)):
                if state.pendingCurrency == currency {
                    // Commit the deferred switch now that a real rate is available.
                    state.pendingCurrency = nil
                    return commitDisplayCurrency(&state, currency: currency, rate: rate)
                }
                // Launch/refresh path for the already-selected currency: just apply the rate.
                guard currency == state.selectedCurrency else { return .none }
                state.currentUSDToDisplayRate = rate
                return .none

            case let .currentCurrencyConversionRateReceived(currency, .failure(error)):
                if state.pendingCurrency == currency {
                    // The deferred switch failed — stay on the previous currency so no
                    // cached USD value is ever relabeled; surface the failure to the UI.
                    state.pendingCurrency = nil
                    state.historicalFXAvailability = .failed(error.message)
                    return .none
                }
                guard currency == state.selectedCurrency else { return .none }
                state.historicalFXAvailability = .failed(error.message)
                return .none

            case let .currencyConversionRefreshCompleted(currency, .success(result)):
                guard currency == state.selectedCurrency, result.currency == state.selectedCurrency else {
                    return .none
                }
                state.currentUSDToDisplayRate = result.currentUSDToDisplayRate
                state.historicalFXAvailability = .available
                return .none

            case let .currencyConversionRefreshCompleted(currency, .failure(error)):
                guard currency == state.selectedCurrency else { return .none }
                state.historicalFXAvailability = .failed(error.message)
                return .none

            case let .startPricePolling(coinIds):
                let request = PricePollingIDResolver.split(coinIds)
                guard request.isEmpty == false else {
                    state.connectionStatus = .idle
                    state.pricePollingIDs = []
                    return .cancel(id: CancelID.pricePolling)
                }
                state.pricePollingIDs = request.allPriceIDs
                state.connectionStatus = .fetching
                return pricePollingEffect(request: request, currency: state.selectedCurrency)

            case let .pricesReceived(update):
                guard update.currency == state.selectedCurrency else { return .none }
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
                state.pricePollingIDs = []
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

private extension AppFeature {
    static let settingsRecheckInterval: Duration = .seconds(10)

    /// Applies a display-currency switch: persists the preference, sets the rate,
    /// clears stale prices, and restarts polling in the new currency. The historical
    /// FX availability is left untouched for non-USD (the historical refresh resolves
    /// it) and marked available for USD, which needs no refresh.
    func commitDisplayCurrency(
        _ state: inout State,
        currency: FiatCurrency,
        rate: Decimal) -> Effect<Action> {
        displayCurrencyPreference.save(currency)
        state.selectedCurrency = currency
        state.currentUSDToDisplayRate = rate
        if currency == .usd {
            state.historicalFXAvailability = .available
        }
        state.prices = [:]
        state.priceChanges24h = [:]
        state.lastPriceUpdate = nil

        let request = PricePollingIDResolver.split(state.pricePollingIDs)
        guard request.isEmpty == false else { return .none }
        state.connectionStatus = .fetching
        return pricePollingEffect(request: request, currency: currency)
    }

    func currencyConversionEffect(currency: FiatCurrency) -> Effect<Action> {
        .run { send in
            let currentRate: Decimal
            do {
                currentRate = try await currencyConversion.fetchCurrentUSDToDisplayRate(currency)
                await send(.currentCurrencyConversionRateReceived(currency, .success(currentRate)))
            } catch {
                await send(.currentCurrencyConversionRateReceived(
                    currency,
                    .failure(CurrencyConversionRefreshError(message: error.localizedDescription))))
                return
            }

            do {
                let historical = try await currencyConversion.refreshHistoricalRates(
                    currency,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
                let result = CurrencyConversionRefreshResult(
                    currency: historical.currency,
                    currentUSDToDisplayRate: currentRate,
                    insertedHistoricalRates: historical.insertedHistoricalRates,
                    updatedHistoricalRates: historical.updatedHistoricalRates)
                await send(.currencyConversionRefreshCompleted(currency, .success(result)))
            } catch {
                await send(.currencyConversionRefreshCompleted(
                    currency,
                    .failure(CurrencyConversionRefreshError(message: error.localizedDescription))))
            }
        }
        .cancellable(id: CancelID.currencyConversion, cancelInFlight: true)
    }

    func pricePollingEffect(request: PricePollingRequest, currency: FiatCurrency) -> Effect<Action> {
        var effects: [Effect<Action>] = [
            coinGeckoPricePollingEffect(request: request, currency: currency)
        ]

        if request.zapperIdentities.isEmpty == false {
            effects.append(.run { send in
                while !Task.isCancelled {
                    guard let zapperFallbackInterval = pricePollingSettings.zapperFallbackInterval() else {
                        try await clock.sleep(for: Self.settingsRecheckInterval)
                        continue
                    }

                    do {
                        let update = try await priceService.fetchZapperPrices(request.zapperIdentities, currency)
                        await send(.pricesReceived(update))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.priceFetchFailed(error))
                    }

                    var elapsed: Duration = .zero
                    while !Task.isCancelled {
                        guard let currentInterval = pricePollingSettings.zapperFallbackInterval() else {
                            break
                        }
                        guard elapsed < currentInterval else { break }
                        let remaining = currentInterval - elapsed
                        let sleepDuration = Self.shorterDuration(remaining, Self.settingsRecheckInterval)
                        try await clock.sleep(for: sleepDuration)
                        elapsed += sleepDuration
                    }
                }
            })
        }

        return .merge(effects)
            .cancellable(id: CancelID.pricePolling, cancelInFlight: true)
    }

    func coinGeckoPricePollingEffect(request: PricePollingRequest, currency: FiatCurrency) -> Effect<Action> {
        let coinRequest = PricePollingRequest(
            coinGeckoIDs: request.coinGeckoIDs,
            zapperIdentities: [])
        let tokenRequest = PricePollingRequest(
            coinGeckoIDs: [],
            zapperIdentities: request.zapperIdentities)

        return .run { send in
            while !Task.isCancelled {
                if coinRequest.isEmpty == false {
                    do {
                        let update = try await priceService.fetchCoinGeckoPrices(coinRequest, currency)
                        await send(.pricesReceived(update))
                    } catch {
                        guard !Task.isCancelled else { return }
                        if tokenRequest.isEmpty {
                            await send(.priceFetchFailed(error))
                        }
                    }
                }

                if tokenRequest.isEmpty == false {
                    do {
                        let update = try await priceService.fetchCoinGeckoPrices(tokenRequest, currency)
                        if coinRequest.isEmpty || update.prices.isEmpty == false || update.changes24h.isEmpty == false {
                            await send(.pricesReceived(update))
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.priceFetchFailed(error))
                    }
                }

                try await clock.sleep(for: pricePollingSettings.refreshInterval())
            }
        }
    }

    static func scheduledSyncSleepDuration(
        now: Date,
        lastZapperSync: Date,
        lastExchangeSync: Date,
        zapperInterval: Duration?,
        exchangeInterval: Duration?) -> Duration {
        var sleepDuration = settingsRecheckInterval

        if let zapperInterval {
            sleepDuration = shorterDuration(
                sleepDuration,
                remainingDuration(interval: zapperInterval, lastSync: lastZapperSync, now: now))
        }

        if let exchangeInterval {
            sleepDuration = shorterDuration(
                sleepDuration,
                remainingDuration(interval: exchangeInterval, lastSync: lastExchangeSync, now: now))
        }

        return sleepDuration
    }

    static func remainingDuration(interval: Duration, lastSync: Date, now: Date) -> Duration {
        let remainingSeconds = timeInterval(for: interval) - now.timeIntervalSince(lastSync)
        guard remainingSeconds > 0 else { return .zero }
        return .seconds(remainingSeconds)
    }

    static func shorterDuration(_ lhs: Duration, _ rhs: Duration) -> Duration {
        lhs < rhs ? lhs : rhs
    }

    static func timeInterval(for duration: Duration) -> TimeInterval {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / attosecondsPerSecond
    }
}

// MARK: - Equatable for Result

extension AppFeature.Action: Equatable {
    // swiftlint:disable:next cyclomatic_complexity
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.appLaunched, .appLaunched): true
        case let (.sectionSelected(l), .sectionSelected(r)): l == r
        case (.settingsSelected, .settingsSelected): true
        case (.syncTapped, .syncTapped): true
        case let (.accountSyncTapped(l), .accountSyncTapped(r)): l == r
        case let (.syncProgressUpdated(l), .syncProgressUpdated(r)): l == r
        case let (.syncCompleted(.success(l)), .syncCompleted(.success(r))): l == r
        case (.syncCompleted(.failure), .syncCompleted(.failure)): true
        case let (.accountSyncCompleted(.success(l)), .accountSyncCompleted(.success(r))): l == r
        case (.accountSyncCompleted(.failure), .accountSyncCompleted(.failure)): true
        case (.startScheduledSync, .startScheduledSync): true
        case (.stopScheduledSync, .stopScheduledSync): true
        case let (.scheduledSyncDue(l), .scheduledSyncDue(r)): l == r
        case let (.scheduledSyncCompleted(.success(l)), .scheduledSyncCompleted(.success(r))): l == r
        case (.scheduledSyncCompleted(.failure), .scheduledSyncCompleted(.failure)): true
        case let (.displayCurrencySelected(l), .displayCurrencySelected(r)): l == r
        case let (
            .currentCurrencyConversionRateReceived(lCurrency, .success(lRate)),
            .currentCurrencyConversionRateReceived(rCurrency, .success(rRate))):
            lCurrency == rCurrency && lRate == rRate
        case let (
            .currentCurrencyConversionRateReceived(lCurrency, .failure(lError)),
            .currentCurrencyConversionRateReceived(rCurrency, .failure(rError))):
            lCurrency == rCurrency && lError == rError
        case let (
            .currencyConversionRefreshCompleted(lCurrency, .success(lResult)),
            .currencyConversionRefreshCompleted(rCurrency, .success(rResult))):
            lCurrency == rCurrency && lResult == rResult
        case let (.currencyConversionRefreshCompleted(lCurrency, .failure(lError)), .currencyConversionRefreshCompleted(rCurrency, .failure(rError))):
            lCurrency == rCurrency && lError == rError
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
