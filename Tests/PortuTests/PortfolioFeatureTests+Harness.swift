import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// The stores and fixtures the portfolio reducer specs share: the projectors and the valuator are
/// counted, the save and settings streams are the test's, and the value chart has a kept source.
extension PortfolioFeatureTests {
    final class Counts: Sendable {
        private let state = Mutex((
            builds: 0,
            valuations: 0,
            requests: [PortfolioProjectionRequest](),
            chartBuilds: 0,
            chartRequests: [PortfolioProjectionRequest]()))

        var builds: Int {
            state.withLock { $0.builds }
        }

        var valuations: Int {
            state.withLock { $0.valuations }
        }

        var requests: [PortfolioProjectionRequest] {
            state.withLock { $0.requests }
        }

        /// The value chart's builds, which the holdings' never count.
        var chartBuilds: Int {
            state.withLock { $0.chartBuilds }
        }

        var chartRequests: [PortfolioProjectionRequest] {
            state.withLock { $0.chartRequests }
        }

        func built(_ request: PortfolioProjectionRequest) {
            state.withLock {
                $0.builds += 1
                $0.requests.append(request)
            }
        }

        func chartBuilt(_ request: PortfolioProjectionRequest) {
            state.withLock {
                $0.chartBuilds += 1
                $0.chartRequests.append(request)
            }
        }

        func valued() {
            state.withLock { $0.valuations += 1 }
        }

        func reset() {
            state.withLock { $0 = (0, 0, [], 0, []) }
        }
    }

    /// Every action the reducer sees, in order, so a test can count what a trigger caused without
    /// ordering the actions around it.
    final class ActionLog: Sendable {
        private let actions = Mutex([AppFeature.Action]())

        func record(_ action: AppFeature.Action) {
            actions.withLock { $0.append(action) }
        }

        func reset() {
            actions.withLock { $0 = [] }
        }

        /// How many actions of one case were sent, whatever their payload.
        func count(of keyPath: CaseKeyPath<AppFeature.Action, some Any>) -> Int {
            actions.withLock { $0.count { $0.is(keyPath) } }
        }

        /// How many actions were sent in all.
        var total: Int {
            actions.withLock { $0.count }
        }

        /// How many conversions of the value chart ran.
        var conversions: Int {
            count(of: \.portfolio.valueChartConverted)
        }

        /// The chart sources the builds delivered, in order.
        var chartSources: [PortfolioValueChartSource] {
            actions.withLock { actions in
                actions.compactMap { action in
                    if case let .portfolio(.valueChartBuilt(source)) = action {
                        source
                    } else {
                        nil
                    }
                }
            }
        }

        /// The watchlists the settings stream delivered, in order.
        var watchlists: [[String]] {
            actions.withLock { actions in
                actions.compactMap { action in
                    if case let .portfolio(.settingsChanged(settings)) = action {
                        settings.watchlistIDs
                    } else {
                        nil
                    }
                }
            }
        }
    }

    /// Lets every effect that can finish on its own run to its end: they share the test's executor,
    /// so they run as it yields.
    static func settle() async {
        await Task.megaYield(count: 50)
    }

    /// `settle()`, then takes the actions the effects sent as received. A test store's `state` is the
    /// state its test has asserted so far, so a non-exhaustive test reads the state they left only
    /// after this.
    static func settle(_ store: TestStoreOf<AppFeature>) async {
        await settle()
        await store.skipReceivedActions(strict: false)
    }

    /// Starts the dashboard task and lets its first builds, valuation and conversion land.
    static func launched(_ store: TestStoreOf<AppFeature>) async -> TestStoreTask {
        let task = await store.send(.portfolio(.task))
        await settle()
        return task
    }

    static func state(
        projection: PortfolioProjection?,
        currency: FiatCurrency = .usd,
        rate: Decimal = 1,
        chart: PortfolioValueChartSource? = nil) -> AppFeature.State {
        var state = AppFeature.State()
        state.selectedCurrency = currency
        state.currentUSDToDisplayRate = rate
        // Today's historical FX is already fetched, so a rate refresh starts no top-up.
        state.historicalFXLastRefreshDayByCurrency[currency] = HistoricalPriceCalendar.utcStartOfDay(for: now)
        state.livePricesUSD = Fixture.livePricesUSD
        state.priceChanges24h = Fixture.liveChanges24h
        state.portfolio.projection = projection
        if projection != nil {
            state.portfolio.store(expected(prices: state.portfolioPriceInputs, settings: state.portfolio.settings, projection: projection))
        }
        if let chart {
            state.portfolio.valueChartSource = chart
            state.portfolio.valueChart = convertedChart(chart, currency: currency, rate: rate)
        }
        return state
    }

    /// `chart` is the source the dashboard kept, with its conversion; `builtChart` is what the chart
    /// projector returns. `initial` changes the starting state, `dependencies` the test's
    /// dependencies, and `log` sees every action.
    static func store(
        counts: Counts,
        projection: PortfolioProjection?,
        built: PortfolioProjection = .empty,
        chart: PortfolioValueChartSource? = nil,
        builtChart: PortfolioValueChartSource = .empty,
        failing: Bool = false,
        failingChart: Bool = false,
        currency: FiatCurrency = .usd,
        rate: Decimal = 1,
        saves: AsyncStream<ModelSaveEvent> = AsyncStream { $0.finish() },
        settings: AsyncStream<DashboardSettings>? = nil,
        current: @escaping @Sendable () -> DashboardSettings = { .defaults },
        clock: TestClock<Duration> = TestClock(),
        now: (@Sendable () -> Date)? = nil,
        log: ActionLog? = nil,
        initial: (inout AppFeature.State) -> Void = { _ in },
        dependencies: (inout DependencyValues) -> Void = { _ in }) -> TestStoreOf<AppFeature> {
        var initialState = Self.state(projection: projection, currency: currency, rate: rate, chart: chart)
        initial(&initialState)
        let fixedNow = Self.now
        let logging = Reduce<AppFeature.State, AppFeature.Action> { _, action in
            log?.record(action)
            return .none
        }
        return TestStore(initialState: initialState) {
            CombineReducers {
                logging
                AppFeature()
            }
        } withDependencies: {
            $0.continuousClock = clock
            $0.currentDate.now = now ?? { fixedNow }
            $0.modelSave.saves = { saves }
            $0.dashboardSettings.current = current
            if let settings {
                $0.dashboardSettings.changes = { settings }
            }
            $0.portfolioProjector.build = { request in
                counts.built(request)
                if failing {
                    throw PortfolioProjectorError(message: "store unavailable")
                }
                return built
            }
            $0.portfolioValueChartProjector.build = { request in
                counts.chartBuilt(request)
                if failingChart {
                    throw PortfolioProjectorError(message: "chart store unavailable")
                }
                return builtChart
            }
            $0.portfolioValuator.value = { request in
                counts.valued()
                return PortfolioValuator.compute(request)
            }
            $0.displayCurrencyPreference.save = { _ in }
            dependencies(&$0)
        }
    }

    static let eurRate = Fixture.decimal("0.95")

    /// A month of the chart in USD: three snapshots, an estimated day before them, and the EUR rows
    /// of the three days up to the last one. Today (noon) takes the live rate until its UTC day
    /// ends, then its own row.
    static let chartSource = PortfolioValueChartSource(
        snapshots: [
            PortfolioValueSnapshotPoint(id: Fixture.uuid(8001), timestamp: Fixture.noon(-2), totalValueUSD: 10000, isPartial: false),
            PortfolioValueSnapshotPoint(id: Fixture.uuid(8002), timestamp: Fixture.noon(-1), totalValueUSD: 11000, isPartial: false),
            PortfolioValueSnapshotPoint(id: Fixture.uuid(8003), timestamp: Fixture.noon(0), totalValueUSD: 12000, isPartial: true)
        ],
        rates: [
            CurrencyConversionRateEntry(baseCurrency: .usd, quoteCurrency: .eur, day: Fixture.day(-2), rate: Fixture.decimal("0.80")),
            CurrencyConversionRateEntry(baseCurrency: .usd, quoteCurrency: .eur, day: Fixture.day(-1), rate: Fixture.decimal("0.90")),
            CurrencyConversionRateEntry(baseCurrency: .usd, quoteCurrency: .eur, day: Fixture.day(0), rate: Fixture.decimal("0.91"))
        ],
        estimatedUSD: [HistoricalPortfolioValuePoint(date: Fixture.day(-3), value: 9000, kind: .estimated)])

    /// `source` as the reducer converts it for the given currency, rate and day.
    static func convertedChart(
        _ source: PortfolioValueChartSource,
        currency: FiatCurrency = .usd,
        rate: Decimal = 1,
        today: Date = now) -> PortfolioValueChartData {
        PortfolioValueChartData.converting(source, currency: currency, usdToDisplayRate: rate, today: today)
    }

    static func expected(
        prices: PortfolioPriceInputs,
        settings: DashboardSettings,
        projection: PortfolioProjection? = projection) -> PortfolioRevaluation? {
        projection.map { PortfolioValuator.compute(PortfolioValuationRequest(projection: $0, prices: prices, settings: settings)) }
    }
}

extension PortfolioFeature.State {
    /// What `revalued` stores: the headline output, and each panel's output in place.
    mutating func store(_ revaluation: PortfolioRevaluation?) {
        valued = revaluation?.valued
        if let revaluation {
            overview.update(with: revaluation.overview)
        }
    }
}

extension PortfolioProjection {
    /// The 18-token valuation fixture as a prepared projection: every input both as a holding and
    /// as an active token. `dropping` leaves out that many leading inputs, so two fixtures differ.
    static func fixture(dropping count: Int = 0, historical: HistoricalMarketPrices = .empty) -> PortfolioProjection {
        let prepared = PortfolioValuation.prepare(
            Array(PortfolioValuationFixture.inputs.dropFirst(count)),
            overrides: PortfolioValuationFixture.overrides,
            mappings: PortfolioValuationFixture.mappings)
        var projection = PortfolioProjection.empty
        projection.holdings = prepared
        projection.activeTokens = prepared
        projection.positionMeta = PortfolioValuationFixture.positions
        projection.overrides = PortfolioValuationFixture.overrides
        projection.mappings = PortfolioValuationFixture.mappings
        projection.historical = historical
        return projection
    }
}
