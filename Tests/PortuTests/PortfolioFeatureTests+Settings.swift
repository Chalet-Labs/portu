import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// The read model's settings: what a change revalues and what it rebuilds (#123, spec V1 and B1).
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
}
