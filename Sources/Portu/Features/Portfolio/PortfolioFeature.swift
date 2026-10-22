import ComposableArchitecture
import Foundation
import os
import PortuCore

/// The portfolio read model (#123): the off-main projection, the settings it is valued with, and the
/// valued output the Sidebar header, the Overview top bar and Overview's polling read. The prices
/// stay with `AppFeature`, which revalues where they change, off the main thread, and sends the
/// result back as `revalued`; this reducer asks for a revaluation (`delegate(.revaluationNeeded)`)
/// when the projection or a valued setting changes.
@Reducer
struct PortfolioFeature {
    @ObservableState
    struct State: Equatable {
        /// `nil` until the first build lands; nothing is valued or polled before it.
        var projection: PortfolioProjection?
        var settings = DashboardSettings.defaults
        var valued: PortfolioValuedOutput?

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
        case revalued(PortfolioValuedOutput)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// The projection or a valued setting changed; the parent revalues with its prices.
            case revaluationNeeded
        }
    }

    static let saveDebounce = Duration.milliseconds(300)

    private enum CancelID {
        case build
        case saveObservation
        case saveDebounce
        case settingsObservation
        case dayRollover
    }

    private static let logger = Logger(subsystem: "com.portu.app", category: "PortfolioReadModel")

    @Dependency(\.portfolioProjector) private var projector
    @Dependency(\.modelSave) private var modelSave
    @Dependency(\.dashboardSettings) private var dashboardSettings
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.currentDate) private var currentDate

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.settings = dashboardSettings.current()
                return .merge(
                    build(state),
                    observeSaves(),
                    observeSettings(from: state.settings),
                    followDayRollover())

            case let .saveObserved(event):
                guard event.touches(PortfolioProjector.readEntityNames) else { return .none }
                return .run { [clock] send in
                    try await clock.sleep(for: Self.saveDebounce)
                    await send(.rebuildRequested)
                }
                .cancellable(id: CancelID.saveDebounce, cancelInFlight: true)

            case .rebuildRequested, .dayRolledOver:
                return build(state)

            case let .projectionBuilt(projection):
                guard projection != state.projection else { return .none }
                state.projection = projection
                return .send(.delegate(.revaluationNeeded))

            case let .projectionBuildFailed(message):
                Self.logger.error("Portfolio projection build failed: \(message, privacy: .public)")
                return .none

            case let .settingsChanged(settings):
                let previous = state.settings
                guard settings != previous else { return .none }
                state.settings = settings
                let rebuilds = settings.dashboard != previous.dashboard
                    || settings.isHistoricalBackfillEnabled != previous.isHistoricalBackfillEnabled
                // The valuator never reads the backfill flag: its change revalues through the
                // projection its rebuild stores.
                let revalues = settings.dashboard != previous.dashboard || settings.watchlistIDs != previous.watchlistIDs
                return .merge(
                    revalues ? .send(.delegate(.revaluationNeeded)) : .none,
                    rebuilds ? build(state) : .none)

            case let .revalued(output):
                // An unchanged result is not written, so its readers are not invalidated.
                if output != state.valued {
                    state.valued = output
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }

    /// The latest build wins: a new one cancels the one in flight. A failure keeps the current
    /// projection (none before the first build) until the next trigger.
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

    private func observeSaves() -> Effect<Action> {
        .run { [modelSave] send in
            for await event in modelSave.saves() {
                await send(.saveObserved(event))
            }
        }
        .cancellable(id: CancelID.saveObservation, cancelInFlight: true)
    }

    /// The stream starts with the current settings, so a change between `current()` and the
    /// subscription is never missed; values equal to the last one sent are dropped.
    private func observeSettings(from initial: DashboardSettings) -> Effect<Action> {
        .run { [dashboardSettings] send in
            var last = initial
            for await settings in dashboardSettings.changes() where settings != last {
                last = settings
                await send(.settingsChanged(settings))
            }
        }
        .cancellable(id: CancelID.settingsObservation, cancelInFlight: true)
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
