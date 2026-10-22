import ComposableArchitecture
import Foundation
import os
import PortuCore

/// The portfolio read model (#123, #124): the off-main projection, the settings it is valued with,
/// the valued output the Sidebar header, the Overview top bar and Overview's polling read, the
/// Overview panels, and the value chart. The prices stay with `AppFeature`, which revalues where
/// they change, off the main thread, and sends the result back as `revalued`; this reducer asks
/// for a revaluation (`delegate(.revaluationNeeded)`) when the projection or a valued setting
/// changes, and for a chart conversion (`delegate(.valueChartConversionNeeded)`) when the chart
/// source or the UTC day changes.
@Reducer
struct PortfolioFeature {
    @ObservableState
    struct State: Equatable {
        /// `nil` until the first build lands; nothing is valued or polled before it.
        var projection: PortfolioProjection?
        var settings = DashboardSettings.defaults
        var valued: PortfolioValuedOutput?
        /// One field per Overview panel, written in place only when it changed.
        var overview = OverviewPanels()
        /// The value chart's month in USD, built by its own projector; `nil` until the first build.
        var valueChartSource: PortfolioValueChartSource?
        /// `valueChartSource` in the display currency.
        var valueChart: PortfolioValueChartData?
        /// The last build's failure, cleared by the next build that lands. The slice shows it on its
        /// dashes, so "unavailable" is not mistaken for "loading".
        var buildError: String?

        /// What a revaluation with `prices` needs, or `nil` before the first build: nothing is valued
        /// then.
        func valuationRequest(_ prices: PortfolioPriceInputs) -> PortfolioValuationRequest? {
            projection.map { PortfolioValuationRequest(projection: $0, prices: prices, settings: settings) }
        }
    }

    enum Action: Equatable {
        /// The dashboard appeared: build once and start following saves, settings and the day.
        case task
        case saveObserved(ModelSaveEvent)
        case rebuildRequested
        case projectionBuilt(PortfolioProjection)
        case projectionBuildFailed(String)
        case settingsChanged(DashboardSettings)
        case dayRolledOver
        /// A revaluation's result, computed off the main thread by the parent's effect.
        case revalued(PortfolioRevaluation)
        case valueChartRebuildRequested
        case valueChartBuilt(PortfolioValueChartSource)
        /// A conversion's result, computed off the main thread by the parent's effect.
        case valueChartConverted(PortfolioValueChartData)
        /// The watchlist's Add and Remove: persisted through the settings client, whose echo then
        /// updates `settings` (UserDefaults stays the one source of truth). Each runs in its own
        /// effect, so two edits sent within microseconds may persist in either order; both persist.
        case watchlistAdded(String)
        case watchlistRemoved(String)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// The projection or a valued setting changed; the parent revalues with its prices.
            case revaluationNeeded
            /// The chart source or the UTC day changed; the parent converts with its rate.
            case valueChartConversionNeeded
        }
    }

    static let saveDebounce = Duration.milliseconds(300)
    /// How long after a failed first build the read model tries again.
    static let firstBuildRetry = Duration.seconds(30)

    private enum CancelID {
        case build
        case observation
        case saveDebounce
        case dayRollover
        case valueChartBuild
        case valueChartSaveDebounce
    }

    private static let logger = Logger(subsystem: "com.portu.app", category: "PortfolioReadModel")

    @Dependency(\.portfolioProjector) private var projector
    @Dependency(\.portfolioValueChartProjector) private var valueChartProjector
    @Dependency(\.modelSave) private var modelSave
    @Dependency(\.dashboardSettings) private var dashboardSettings
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.currentDate) private var currentDate

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.settings = dashboardSettings.current()
                // A re-run (the window reopened) values the projection and converts the chart it
                // kept: settings may have changed meanwhile, and the closing window may have
                // cancelled a valuation or a conversion. An equal rebuild would redo neither.
                return .merge(
                    observeThenBuild(from: state.settings),
                    followDayRollover(),
                    state.projection != nil ? .send(.delegate(.revaluationNeeded)) : .none,
                    state.valueChartSource != nil ? .send(.delegate(.valueChartConversionNeeded)) : .none)

            case let .saveObserved(event):
                return .merge(
                    event.touches(PortfolioProjector.readEntityNames)
                        ? debounced(.rebuildRequested, id: CancelID.saveDebounce)
                        : .none,
                    event.touches(PortfolioValueChartProjector.readEntityNames)
                        ? debounced(.valueChartRebuildRequested, id: CancelID.valueChartSaveDebounce)
                        : .none)

            case .rebuildRequested:
                return build(state)

            case .dayRolledOver:
                // The chart's "today" moves even when its rebuild is equal.
                return .merge(
                    build(state),
                    buildValueChart(state),
                    .send(.delegate(.valueChartConversionNeeded)))

            case .valueChartRebuildRequested:
                return buildValueChart(state)

            case let .valueChartBuilt(source):
                guard source != state.valueChartSource else { return .none }
                state.valueChartSource = source
                return .send(.delegate(.valueChartConversionNeeded))

            case let .valueChartConverted(chart):
                if chart != state.valueChart {
                    state.valueChart = chart
                }
                return .none

            case let .projectionBuilt(projection):
                state.buildError = nil
                guard projection != state.projection else { return .none }
                state.projection = projection
                return .send(.delegate(.revaluationNeeded))

            case let .projectionBuildFailed(message):
                // The same text the dashed total shows as its tooltip, so not worth redacting.
                Self.logger.error("Portfolio projection build failed: \(message, privacy: .public)")
                state.buildError = message
                // With no projection yet nothing is valued or polled, so don't wait for a save that
                // may be hours away; any newer build cancels the retry.
                guard state.projection == nil else { return .none }
                return .run { [clock] send in
                    try await clock.sleep(for: Self.firstBuildRetry)
                    await send(.rebuildRequested)
                }
                .cancellable(id: CancelID.build, cancelInFlight: true)

            case let .settingsChanged(settings):
                let previous = state.settings
                guard settings != previous else { return .none }
                state.settings = settings
                let backfillChanged = settings.isHistoricalBackfillEnabled != previous.isHistoricalBackfillEnabled
                let rebuilds = settings.dashboard != previous.dashboard || backfillChanged
                // The valuator never reads the backfill flag: its change revalues through the
                // projection its rebuild stores, and converts through the chart source its rebuild stores.
                let revalues = settings.dashboard != previous.dashboard || settings.watchlistIDs != previous.watchlistIDs
                return .merge(
                    revalues ? .send(.delegate(.revaluationNeeded)) : .none,
                    rebuilds ? build(state) : .none,
                    backfillChanged ? buildValueChart(state) : .none)

            case let .revalued(revaluation):
                // An unchanged result is not written, so its readers are not invalidated. The
                // panels are written field by field in place, and an equal field is skipped.
                if revaluation.valued != state.valued {
                    state.valued = revaluation.valued
                }
                state.overview.update(with: revaluation.overview)
                return .none

            case let .watchlistAdded(coinGeckoId):
                return .run { [dashboardSettings] _ in
                    dashboardSettings.addWatchlistID(coinGeckoId)
                }

            case let .watchlistRemoved(coinGeckoId):
                return .run { [dashboardSettings] _ in
                    dashboardSettings.removeWatchlistID(coinGeckoId)
                }

            case .delegate:
                return .none
            }
        }
    }

    /// The latest build wins: a new one cancels the one in flight. A failure keeps the current
    /// projection; with none yet, it retries after `firstBuildRetry`, and any trigger retries sooner.
    private func build(_ state: State) -> Effect<Action> {
        let request = PortfolioProjectionRequest(
            isHistoricalBackfillEnabled: state.settings.isHistoricalBackfillEnabled,
            now: currentDate.now())
        return .run { [projector] send in
            let projection = try await projector.build(request)
            await send(.projectionBuilt(projection))
        } catch: { error, send in
            await send(.projectionBuildFailed(String(describing: error)))
        }
        .cancellable(id: CancelID.build, cancelInFlight: true)
    }

    /// The chart's latest build wins too. A failed build keeps the chart already shown (an empty or
    /// wrongly converted month would misstate the history) and is logged; the next trigger retries.
    private func buildValueChart(_ state: State) -> Effect<Action> {
        let request = PortfolioProjectionRequest(
            isHistoricalBackfillEnabled: state.settings.isHistoricalBackfillEnabled,
            now: currentDate.now())
        return .run { [valueChartProjector] send in
            let source = try await valueChartProjector.build(request)
            await send(.valueChartBuilt(source))
        } catch: { error, _ in
            guard !(error is CancellationError) else { return }
            Self.logger.error("Value chart build failed: \(String(describing: error), privacy: .public)")
        }
        .cancellable(id: CancelID.valueChartBuild, cancelInFlight: true)
    }

    /// A burst of saves rebuilds once, `saveDebounce` after the last.
    private func debounced(_ action: Action, id: CancelID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.saveDebounce)
            await send(action)
        }
        .cancellable(id: id, cancelInFlight: true)
    }

    /// Subscribes to saves and settings, and only then asks for the first builds, so a save or a
    /// settings change that lands while they run is seen. The settings stream starts with the
    /// current settings; values equal to the last one sent are dropped.
    private func observeThenBuild(from initial: DashboardSettings) -> Effect<Action> {
        .run { [modelSave, dashboardSettings] send in
            let saves = modelSave.saves()
            let changes = dashboardSettings.changes()
            await send(.rebuildRequested)
            await send(.valueChartRebuildRequested)
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await event in saves {
                        await send(.saveObserved(event))
                    }
                }
                group.addTask {
                    var last = initial
                    for await settings in changes where settings != last {
                        last = settings
                        await send(.settingsChanged(settings))
                    }
                }
            }
        }
        .cancellable(id: CancelID.observation, cancelInFlight: true)
    }

    /// The historical window starts at a UTC day boundary, so the projection is rebuilt at each UTC
    /// midnight even without a save. Each wait is measured from a fresh `now`, so a timer that fires
    /// early only schedules another rebuild.
    private func followDayRollover() -> Effect<Action> {
        .run { [clock, currentDate] send in
            while true {
                let now = currentDate.now()
                let nextMidnight = HistoricalPriceCalendar.utcStartOfDay(for: now).addingTimeInterval(86400)
                try await clock.sleep(for: .seconds(nextMidnight.timeIntervalSince(now)))
                await send(.dayRolledOver)
            }
        }
        .cancellable(id: CancelID.dayRollover, cancelInFlight: true)
    }
}
