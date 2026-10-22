import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// How one chart build ends (#124, spec C2): the latest wins, and a failed one changes nothing. The
/// chart is built on its own, so what happens to it never reaches the headline or the holdings.
extension PortfolioFeatureTests {
    /// The latest chart build wins: one still running when a newer starts is cancelled, so the older
    /// source never lands, whatever it would have returned.
    @Test func `a newer chart build wins over a slower older one`() async {
        let clock = TestClock()
        let calls = Mutex(0)
        var older = Self.chartSource
        older.snapshots.removeFirst()
        var newer = Self.chartSource
        newer.snapshots.removeLast()
        let log = ActionLog()
        let store = Self.store(
            counts: Counts(),
            projection: Self.projection,
            clock: clock,
            log: log,
            dependencies: {
                $0.portfolioValueChartProjector.build = { [older, newer] _ in
                    let call = calls.withLock { value in
                        value += 1
                        return value
                    }
                    if call == 1 {
                        // Still building when the next trigger lands.
                        try await clock.sleep(for: .seconds(5))
                        return older
                    }
                    return newer
                }
            })
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.portfolio(.valueChartRebuildRequested))
        await store.send(.portfolio(.valueChartRebuildRequested))
        await Self.settle(store)
        await clock.advance(by: .seconds(10))
        await Self.settle(store)

        #expect(calls.withLock { $0 } == 2)
        #expect(log.chartSources == [newer], "the older build was cancelled before it could land")
        #expect(store.state.portfolio.valueChartSource == newer)
        #expect(store.state.portfolio.valueChart == Self.convertedChart(newer))
    }

    /// A failed chart build with a chart kept leaves what shows as it is: the source, the converted
    /// chart, the headline and the holdings are untouched, and the holdings' error is not set. Only the
    /// chart's own error is recorded, and no retry is scheduled: the next trigger builds again.
    @Test func `a failed chart build with a chart kept records its error and changes nothing else`() async {
        let counts = Counts()
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: Self.chartSource,
            failingChartBuilds: .max,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let before = store.state.portfolio

        let task = await store.send(.portfolio(.task))
        await Self.settle(store)
        await clock.advance(by: .seconds(3600))
        await Self.settle(store)
        await task.cancel()

        let portfolio = store.state.portfolio
        var expected = before
        expected.valueChartBuildError = Self.chartBuildError
        #expect(portfolio == expected, "only the chart's error differs")
        #expect(portfolio.valueChartSource == Self.chartSource)
        #expect(portfolio.valueChart == before.valueChart)
        #expect(portfolio.valued == before.valued)
        #expect(portfolio.buildError == nil)
        #expect(counts.chartBuilds == 1, "no retry")
        #expect(counts.builds == 1, "the holdings build ran")
    }

    /// With no chart yet, a failed build retries as the first holdings build does, after
    /// `firstBuildRetry`, and the build that lands clears the error and is converted. The error is the
    /// chart's: the holdings' stays unset.
    @Test func `a failed first chart build retries after the first build retry until one lands`() async {
        let counts = Counts()
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            builtChart: Self.chartSource,
            failingChartBuilds: 1,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await store.send(.portfolio(.task))
        await Self.settle(store)
        #expect(counts.chartBuilds == 1)
        #expect(store.state.portfolio.valueChartSource == nil)
        #expect(store.state.portfolio.valueChart == nil)
        #expect(store.state.portfolio.valueChartBuildError == Self.chartBuildError)
        #expect(store.state.portfolio.buildError == nil)

        await clock.advance(by: PortfolioFeature.firstBuildRetry - .seconds(1))
        await Self.settle(store)
        #expect(counts.chartBuilds == 1, "the retry waits its time")

        await clock.advance(by: .seconds(1))
        await Self.settle(store)
        #expect(counts.chartBuilds == 2)
        #expect(store.state.portfolio.valueChartSource == Self.chartSource)
        #expect(store.state.portfolio.valueChart == Self.convertedChart(Self.chartSource))
        #expect(store.state.portfolio.valueChartBuildError == nil)

        await clock.advance(by: .seconds(3600))
        await Self.settle(store)
        await task.cancel()
        #expect(counts.chartBuilds == 2, "no retry once a build has landed")
    }

    /// A trigger that comes before the retry builds sooner, and the retry it supersedes never runs.
    @Test func `a chart save supersedes the pending first chart build retry`() async {
        let counts = Counts()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            builtChart: Self.chartSource,
            failingChartBuilds: 1,
            saves: saves.stream,
            clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await store.send(.portfolio(.task))
        await Self.settle(store)
        #expect(counts.chartBuilds == 1)

        saves.continuation.yield(.entities(["PortfolioSnapshot"]))
        await clock.advance(by: PortfolioFeature.saveDebounce)
        await Self.settle(store)
        #expect(counts.chartBuilds == 2)
        #expect(store.state.portfolio.valueChartSource == Self.chartSource)
        #expect(store.state.portfolio.valueChartBuildError == nil)

        await clock.advance(by: PortfolioFeature.firstBuildRetry)
        await Self.settle(store)
        await task.cancel()
        #expect(counts.chartBuilds == 2, "the superseded retry never ran")
    }

    /// A failure doesn't wedge the chart: the next trigger builds again, and a build that lands
    /// clears the error even when its source is the one already kept.
    @Test func `a chart build that lands clears the error even when its source is equal`() async {
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            chart: Self.chartSource,
            builtChart: Self.chartSource,
            failingChartBuilds: 1,
            log: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.portfolio(.valueChartRebuildRequested))
        await Self.settle(store)
        #expect(store.state.portfolio.valueChartBuildError == Self.chartBuildError)
        #expect(store.state.portfolio.valueChartSource == Self.chartSource)

        await store.send(.portfolio(.valueChartRebuildRequested))
        await Self.settle(store)

        #expect(counts.chartBuilds == 2)
        #expect(store.state.portfolio.valueChartBuildError == nil)
        #expect(store.state.portfolio.valueChartSource == Self.chartSource)
        #expect(log.conversions == 0, "the source did not change")
    }
}
