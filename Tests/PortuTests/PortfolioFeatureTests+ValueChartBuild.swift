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

    /// A failed chart build is logged and nothing more: the chart keeps the source it has, or stays
    /// dashed when it has none; the headline and the holdings are untouched, no error is recorded for
    /// the slice (the chart's failure is no portfolio failure), and no retry is scheduled.
    @Test(arguments: [true, false])
    func `a failed chart build changes nothing and schedules no retry`(keepsSource: Bool) async {
        let counts = Counts()
        let log = ActionLog()
        let clock = TestClock()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            chart: keepsSource ? Self.chartSource : nil,
            failingChart: true,
            clock: clock,
            log: log)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let before = store.state.portfolio

        let task = await store.send(.portfolio(.task))
        await Self.settle(store)
        await clock.advance(by: .seconds(3600))
        await Self.settle(store)
        await task.cancel()

        let portfolio = store.state.portfolio
        #expect(counts.chartBuilds == 1, "no retry")
        #expect(counts.builds == 1, "the holdings build ran")
        #expect(log.count(of: \.portfolio.valueChartBuilt) == 0)
        #expect(portfolio.valueChartSource == (keepsSource ? Self.chartSource : nil))
        #expect(portfolio.valueChart == before.valueChart)
        #expect(portfolio.buildError == nil)
        #expect(portfolio.valued == before.valued)
        #expect(portfolio == before)
    }

    /// A failure doesn't wedge the chart: the next trigger builds it again.
    @Test func `the next chart trigger builds again after a failed one`() async {
        let calls = Mutex(0)
        let source = Self.chartSource
        let store = Self.store(
            counts: Counts(),
            projection: Self.projection,
            dependencies: {
                $0.portfolioValueChartProjector.build = { _ in
                    let call = calls.withLock { value in
                        value += 1
                        return value
                    }
                    guard call > 1 else { throw PortfolioProjectorError(message: "chart store unavailable") }
                    return source
                }
            })
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.portfolio(.valueChartRebuildRequested))
        await Self.settle(store)
        #expect(store.state.portfolio.valueChartSource == nil)
        await store.send(.portfolio(.valueChartRebuildRequested))
        await Self.settle(store)

        #expect(calls.withLock { $0 } == 2)
        #expect(store.state.portfolio.valueChartSource == source)
        #expect(store.state.portfolio.valueChart == Self.convertedChart(source))
    }
}
