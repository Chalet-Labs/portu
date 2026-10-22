import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// What builds and converts the value chart (#124, spec C2 and C3): its build triggers beside the
/// holdings', and the conversions of the source it keeps. The chart source is `chartSource`, a
/// month in USD; the chart projector and the holdings projector are counted separately.
extension PortfolioFeatureTests {
    // MARK: - C2: when the chart builds

    /// A save to an entity the chart reads builds it once, `saveDebounce` after the save.
    @Test(arguments: PortfolioValueChartProjector.readEntityNames.sorted())
    func `a save to a chart entity builds the chart once after the debounce`(_ entity: String) async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            saves: saves.stream,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()

        saves.continuation.yield(.entities([entity]))
        await clock.advance(by: PortfolioFeature.saveDebounce - .milliseconds(1))
        await Self.settle()
        #expect(counts.chartBuilds == 0, "the debounce has not elapsed")
        await clock.advance(by: .milliseconds(1))
        await Self.settle()
        await task.cancel()

        #expect(counts.chartBuilds == 1)
    }

    /// Each save moves the debounce: the chart builds once, `saveDebounce` after the last of them.
    @Test func `a burst of chart saves builds the chart once after the last`() async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            saves: saves.stream,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()

        saves.continuation.yield(.entities(["PortfolioSnapshot"]))
        await clock.advance(by: .milliseconds(200))
        saves.continuation.yield(.entities(["AssetSnapshot", "CurrencyConversionRatePoint"]))
        await clock.advance(by: .milliseconds(200))
        await Self.settle()
        #expect(counts.chartBuilds == 0, "the second save moved the debounce")
        await clock.advance(by: .milliseconds(100))
        await Self.settle()
        await task.cancel()

        #expect(counts.chartBuilds == 1)
        #expect(counts.builds == 0)
    }

    /// The holdings' rows are not the chart's: the position, token, account, mapping and category
    /// saves rebuild the holdings and leave the chart as it is.
    @Test(arguments: PortfolioProjector.readEntityNames.subtracting(PortfolioValueChartProjector.readEntityNames).sorted())
    func `a save only the holdings read builds no chart`(_ entity: String) async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            saves: saves.stream,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()

        saves.continuation.yield(.entities([entity]))
        await clock.advance(by: .seconds(1))
        await Self.settle()
        await task.cancel()

        #expect(counts.builds == 1)
        #expect(counts.chartBuilds == 0)
    }

    /// A sync's snapshot save and a rate refresh rebuild the chart, and never the holdings.
    @Test(arguments: PortfolioValueChartProjector.readEntityNames.subtracting(PortfolioProjector.readEntityNames).sorted())
    func `a save only the chart reads builds no holdings`(_ entity: String) async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            saves: saves.stream,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()

        saves.continuation.yield(.entities([entity]))
        await clock.advance(by: .seconds(1))
        await Self.settle()
        await task.cancel()

        #expect(counts.builds == 0)
        #expect(counts.chartBuilds == 1)
    }

    /// The first chart build is asked for only once saves are followed, as the first holdings
    /// build is, so a save that lands while it runs is never lost.
    @Test func `the first chart build starts only after saves are followed`() async {
        let subscribed = Mutex(false)
        // Builds that started before (`early`) and after (`followed`) saves were subscribed.
        let builds = Mutex((early: 0, followed: 0))
        let store = TestStore(initialState: Self.state(projection: nil)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.currentDate.now = { Self.now }
            $0.modelSave.saves = {
                subscribed.withLock { $0 = true }
                return AsyncStream { $0.finish() }
            }
            $0.portfolioValueChartProjector.build = { _ in
                let followed = subscribed.withLock { $0 }
                builds.withLock { followed ? ($0.followed += 1) : ($0.early += 1) }
                return .empty
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await Self.launched(store)
        await task.cancel()

        #expect(builds.withLock { $0.followed } == 1)
        #expect(builds.withLock { $0.early } == 0, "a chart build started before saves were followed")
    }

    // MARK: - C3: when the chart converts

    /// The chart is not valued with the prices: a tick revalues the panels and leaves it be.
    @Test func `a price tick converts nothing`() async {
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(counts: counts, projection: Self.projection, chart: Self.chartSource, log: log)

        await store.send(.pricesReceived(PriceUpdate(prices: ["ethereum": 3100], changes24h: [:]))) {
            $0.livePricesUSD["ethereum"] = 3100
            $0.lastPriceUpdate = Self.now
        }
        await store.receive(\.portfolio.revalued) {
            $0.portfolio.store(Self.expected(prices: $0.portfolioPriceInputs, settings: $0.portfolio.settings))
        }
        await Self.settle()

        #expect(log.conversions == 0)
        #expect(counts.chartBuilds == 0)
        #expect(store.state.portfolio.valueChart == Self.convertedChart(Self.chartSource))
    }

    /// A committed switch revalues the panels and converts the chart: two effects that land in
    /// either order, so the test takes both as received and checks the state they leave.
    @Test func `a committed currency switch converts the chart once`() async {
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            chart: Self.chartSource,
            currency: .eur,
            rate: Self.eurRate,
            log: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.displayCurrencySelected(.usd)) {
            $0.selectedCurrency = .usd
            $0.currentUSDToDisplayRate = 1
        }
        await Self.settle(store)

        let state = store.state
        #expect(state.portfolio.valueChart == Self.convertedChart(Self.chartSource))
        #expect(state.portfolio.valued == Self.expected(prices: state.portfolioPriceInputs, settings: state.portfolio.settings)?.valued)
        #expect(log.conversions == 1)
        #expect(counts.valuations == 1)
        #expect(counts.chartBuilds == 0)
        #expect(log.total == 3, "the switch, its revaluation and its conversion")
    }

    /// The source keeps every quote currency, so a switch from USD to EUR needs no rebuild: past
    /// days take their EUR rows, today the live rate, and a day with no row the live rate too.
    @Test func `a switch from USD to EUR converts past points with the EUR rows`() async {
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            chart: Self.chartSource,
            log: log,
            initial: { $0.pendingCurrency = .eur })
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.currentCurrencyConversionRateReceived(.eur, .success(Self.eurRate)))
        await Self.settle(store)
        await store.skipInFlightEffects(strict: false)

        let chart = store.state.portfolio.valueChart
        #expect(log.conversions == 1)
        #expect(counts.chartBuilds == 0, "the switch needs no new source")
        #expect(chart == Self.convertedChart(Self.chartSource, currency: .eur, rate: Self.eurRate))
        #expect(chart?.currencyCode == "EUR")
        #expect(chart?.snapshots.map(\.value) == [8000, 9900, 11400], "rows 0.80 and 0.90, then today at the live 0.95")
        #expect(chart?.estimated.map(\.value) == [8550], "no row on the estimated day: the live rate")
    }

    @Test func `a refreshed rate converts the chart once`() async {
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            chart: Self.chartSource,
            currency: .eur,
            rate: Self.eurRate,
            log: log)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let refreshed = Fixture.decimal("0.96")

        await store.send(.currentCurrencyConversionRateReceived(.eur, .success(refreshed))) {
            $0.currentUSDToDisplayRate = refreshed
        }
        await Self.settle(store)

        let state = store.state
        #expect(state.portfolio.valueChart == Self.convertedChart(Self.chartSource, currency: .eur, rate: refreshed))
        #expect(state.portfolio.valued == Self.expected(prices: state.portfolioPriceInputs, settings: state.portfolio.settings)?.valued)
        #expect(log.conversions == 1)
        #expect(counts.valuations == 1)
        #expect(log.total == 3, "the refresh, its revaluation and its conversion")
    }

    /// The periodic refresh sends the rate it already has: the panels are revalued and the chart
    /// converted again, and the state is as it was (the observation specs show nothing re-renders).
    @Test func `an equal rate refresh stores nothing`() async {
        let log = ActionLog()
        let store = Self.store(
            counts: Counts(),
            projection: Self.projection,
            chart: Self.chartSource,
            currency: .eur,
            rate: Self.eurRate,
            log: log)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let before = store.state

        await store.send(.currentCurrencyConversionRateReceived(.eur, .success(Self.eurRate)))
        await Self.settle(store)

        #expect(store.state == before)
        #expect(log.conversions == 1)
        #expect(log.count(of: \.portfolio.revalued) == 1)
        #expect(log.total == 3, "the refresh, its revaluation and its conversion")
    }

    @Test func `a changed chart source converts once and an equal one converts nothing`() async {
        let store = Self.store(counts: Counts(), projection: Self.projection, chart: Self.chartSource, currency: .eur, rate: Self.eurRate)
        var moved = Self.chartSource
        moved.snapshots.append(PortfolioValueSnapshotPoint(
            id: Fixture.uuid(8004),
            timestamp: Fixture.noon(0).addingTimeInterval(3600),
            totalValueUSD: 12500,
            isPartial: false))

        await store.send(.portfolio(.valueChartBuilt(Self.chartSource)))
        await store.send(.portfolio(.valueChartBuilt(moved))) {
            $0.portfolio.valueChartSource = moved
        }
        await store.receive(\.portfolio.delegate.valueChartConversionNeeded)
        await store.receive(\.portfolio.valueChartConverted) {
            $0.portfolio.valueChart = Self.convertedChart(moved, currency: .eur, rate: Self.eurRate)
        }
    }

    /// At 23:59:59 UTC the day's own snapshot takes the live rate; a second later the day is past and
    /// takes its stored row. The day's rebuilds are equal, and the conversion still runs, once.
    @Test func `the day rolling over converts the chart once even when the rebuilds are equal`() async {
        let lastSecond = Fixture.day(1).addingTimeInterval(-1)
        let firstSecond = Fixture.day(1).addingTimeInterval(1)
        let now = Mutex(lastSecond)
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            currency: .eur,
            rate: Self.eurRate,
            now: { now.withLock { $0 } },
            log: log)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let before = store.state.portfolio.valueChart

        now.withLock { $0 = firstSecond }
        await store.send(.portfolio(.dayRolledOver))
        await Self.settle(store)

        let after = store.state.portfolio.valueChart
        #expect(counts.builds == 1)
        #expect(counts.chartBuilds == 1)
        #expect(log.conversions == 1)
        #expect(before?.snapshots.last?.value == 11400, "12,000 at the live 0.95 until the UTC day ends")
        #expect(after?.snapshots.last?.value == 10920, "12,000 at the day's own row, 0.91, from the next second")
        #expect(after == Self.convertedChart(Self.chartSource, currency: .eur, rate: Self.eurRate, today: firstSecond))
    }

    /// An equal chart build changes nothing and converts nothing.
    @Test func `a chart rebuild equal to the kept source converts nothing`() async {
        let counts = Counts()
        let store = Self.store(counts: counts, projection: Self.projection, chart: Self.chartSource, builtChart: Self.chartSource)

        await store.send(.portfolio(.valueChartRebuildRequested))
        await store.receive(\.portfolio.valueChartBuilt)

        #expect(counts.chartBuilds == 1)
    }

    /// What a closed dashboard window leaves behind: its conversion cancelled before it landed, or
    /// a UTC midnight it never saw.
    enum Leftover: CaseIterable {
        case cancelledConversion
        case missedMidnight
    }

    /// The window reopened: its task converts the chart it kept, once, though the rebuilds it starts
    /// are equal to what is kept.
    @Test(arguments: Leftover.allCases)
    func `a re run of the task converts the chart it kept`(_ leftover: Leftover) async {
        let nextDay = Fixture.day(1).addingTimeInterval(1)
        let now = Mutex(leftover == .missedMidnight ? nextDay : Self.now)
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            currency: .eur,
            rate: Self.eurRate,
            now: { now.withLock { $0 } },
            log: log,
            initial: {
                if leftover == .cancelledConversion {
                    $0.portfolio.valueChart = nil
                }
            })
        store.exhaustivity = .off(showSkippedAssertions: false)
        let kept = store.state.portfolio.valueChart

        let task = await Self.launched(store)
        await Self.settle(store)
        await task.cancel()

        let today = leftover == .missedMidnight ? nextDay : Self.now
        #expect(log.conversions == 1)
        #expect(store.state.portfolio.valueChart == Self.convertedChart(Self.chartSource, currency: .eur, rate: Self.eurRate, today: today))
        #expect(store.state.portfolio.valueChart != kept)
        #expect(counts.chartBuilds == 1)
    }
}
