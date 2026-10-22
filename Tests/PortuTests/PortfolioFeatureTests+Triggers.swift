import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// What the read model follows: settings (what a change revalues and rebuilds), its subscriptions
/// and its first-build retry (#123, spec V1, B1 and B4).
extension PortfolioFeatureTests {
    // MARK: - V1/B1: settings

    @Test func `a dashboard setting change revalues once and rebuilds`() async {
        let counts = Counts()
        let settings = AsyncStream.makeStream(of: DashboardSettings.self)
        let store = Self.store(counts: counts, projection: Self.projection, built: Self.projection, settings: settings.stream)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        counts.reset()

        let showAll = DashboardSettings(dashboard: .showAll, isHistoricalBackfillEnabled: false, watchlistIDs: [])
        settings.continuation.yield(showAll)
        await store.receive(\.portfolio.settingsChanged)
        await store.receive(\.portfolio.delegate.revaluationNeeded)
        // The revaluation and the rebuild run concurrently and land in either order. Cancelling the
        // task cancels the effects its actions started, so both are received first.
        for _ in 0 ..< 2 {
            await store.receive { action in
                switch action {
                case .portfolio(.revalued), .portfolio(.projectionBuilt): true
                default: false
                }
            }
        }
        await task.cancel()

        #expect(store.state.portfolio.settings == showAll)
        #expect(counts.builds == 1)
        #expect(counts.valuations == 1, "the rebuild is equal, so it adds no revaluation")
        #expect(store.state.portfolio.valued == Self.expected(prices: store.state.portfolioPriceInputs, settings: showAll))
    }

    @Test func `a watchlist change revalues once and rebuilds nothing`() async {
        let counts = Counts()
        let settings = AsyncStream.makeStream(of: DashboardSettings.self)
        let store = Self.store(counts: counts, projection: Self.projection, built: Self.projection, settings: settings.stream)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        counts.reset()

        let watching = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: false, watchlistIDs: ["cardano"])
        settings.continuation.yield(watching)
        await store.receive(\.portfolio.settingsChanged)
        await store.receive(\.portfolio.delegate.revaluationNeeded)
        await store.receive(\.portfolio.revalued)
        await task.cancel()

        #expect(counts.builds == 0)
        #expect(counts.valuations == 1)
        #expect(store.state.portfolio.valued?.pricePollingIDs.last == "cardano")
    }

    /// The window closed and reopened: the task runs again and values settings changed meanwhile,
    /// even though the rebuild it starts is equal.
    @Test func `a re run of the task values settings changed while it was away`() async {
        let counts = Counts()
        let current = Mutex(DashboardSettings.defaults)
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            current: { current.withLock { $0 } })
        store.exhaustivity = .off(showSkippedAssertions: false)
        let first = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        await first.cancel()
        counts.reset()

        let watching = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: false, watchlistIDs: ["cardano"])
        current.withLock { $0 = watching }
        let second = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.delegate.revaluationNeeded)
        await store.receive(\.portfolio.revalued)
        await second.cancel()

        #expect(store.state.portfolio.settings == watching)
        #expect(counts.valuations == 1)
        #expect(store.state.portfolio.valued?.pricePollingIDs.last == "cardano")
    }

    @Test func `a backfill change rebuilds and revalues only through the new projection`() async {
        let counts = Counts()
        let settings = AsyncStream.makeStream(of: DashboardSettings.self)
        let withBook = PortfolioProjection.fixture(historical: Fixture.historical)
        let store = Self.store(counts: counts, projection: Self.projection, built: withBook, settings: settings.stream)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        await store.receive(\.portfolio.delegate.revaluationNeeded)
        await store.receive(\.portfolio.revalued)
        counts.reset()

        let enabled = DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: true, watchlistIDs: [])
        settings.continuation.yield(enabled)
        await store.receive(\.portfolio.settingsChanged)
        await store.receive(\.portfolio.projectionBuilt)
        await task.cancel()

        #expect(counts.builds == 1)
        #expect(counts.requests.last?.isHistoricalBackfillEnabled == true)
        #expect(counts.valuations == 0, "the rebuilt projection is equal to the one already stored")
    }

    // MARK: - B1: subscriptions

    /// The first build is asked for only once saves are followed, so a save that lands while it
    /// runs is never lost.
    @Test func `the first build starts only after saves are followed`() async {
        let subscribed = Mutex(false)
        // Builds that started before (`early`) and after (`followed`) saves were subscribed.
        let builds = Mutex((early: 0, followed: 0))
        let projection = Self.projection
        let store = TestStore(initialState: Self.state(projection: nil)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.currentDate.now = { Self.now }
            $0.modelSave.saves = {
                subscribed.withLock { $0 = true }
                return AsyncStream { $0.finish() }
            }
            $0.portfolioProjector.build = { _ in
                let followed = subscribed.withLock { $0 }
                builds.withLock { followed ? ($0.followed += 1) : ($0.early += 1) }
                return projection
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuilt)
        await task.cancel()

        #expect(builds.withLock { $0.followed } == 1)
        #expect(builds.withLock { $0.early } == 0, "a build started before saves were followed")
    }

    // MARK: - B4: the first-build retry

    /// A save while the first-build retry waits builds sooner, and the retry it supersedes never runs.
    @Test func `a save supersedes the pending first build retry`() async {
        let clock = TestClock()
        let saves = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let calls = Mutex(0)
        let projection = Self.projection
        let store = TestStore(initialState: Self.state(projection: nil)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.currentDate.now = { Self.now }
            $0.modelSave.saves = { saves.stream }
            $0.portfolioProjector.build = { _ in
                let call = calls.withLock { value in
                    value += 1
                    return value
                }
                guard call > 1 else { throw PortfolioProjectorError(message: "store unavailable") }
                return projection
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        let task = await store.send(.portfolio(.task))
        await store.receive(\.portfolio.projectionBuildFailed)
        saves.continuation.yield(.entities(["Position"]))
        await clock.advance(by: PortfolioFeature.saveDebounce)
        await store.receive(\.portfolio.projectionBuilt)
        await clock.advance(by: PortfolioFeature.firstBuildRetry)
        await task.cancel()

        #expect(calls.withLock { $0 } == 2, "the superseded retry built again")
        #expect(store.state.portfolio.projection == projection)
        #expect(store.state.portfolio.buildError == nil)
    }
}
