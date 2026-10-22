import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// The watchlist's Add and Remove (#124, spec W1): the reducer only persists them through the
/// settings client, and its state follows the client's stream, so an echo can never revert an edit.
extension PortfolioFeatureTests {
    nonisolated private static func watching(_ ids: [String]) -> DashboardSettings {
        var settings = DashboardSettings.defaults
        settings.watchlistIDs = ids
        return settings
    }

    /// The action persists and changes nothing else; the settings echo moves the state and
    /// revalues once.
    @Test func `an added coin is persisted once and its echo revalues once`() async {
        let counts = Counts()
        let added = Mutex([String]())
        let settings = AsyncStream.makeStream(of: DashboardSettings.self)
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            settings: settings.stream,
            dependencies: { $0.dashboardSettings.addWatchlistID = { id in added.withLock { $0.append(id) } } })
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()

        await store.send(.portfolio(.watchlistAdded("cardano")))
        await Self.settle(store)
        #expect(added.withLock { $0 } == ["cardano"])
        #expect(store.state.portfolio.settings.watchlistIDs.isEmpty, "the state follows the settings, not the action")
        #expect(counts.valuations == 0)

        settings.continuation.yield(Self.watching(["cardano"]))
        await Self.settle(store)
        await task.cancel()

        #expect(store.state.portfolio.settings.watchlistIDs == ["cardano"])
        #expect(store.state.portfolio.valued?.pricePollingIDs.last == "cardano")
        #expect(counts.valuations == 1)
        #expect(counts.builds == 0)
        #expect(counts.chartBuilds == 0)
    }

    @Test func `a removed coin is persisted once and its echo revalues once`() async {
        let counts = Counts()
        let removed = Mutex([String]())
        let settings = AsyncStream.makeStream(of: DashboardSettings.self)
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            settings: settings.stream,
            current: { Self.watching(["cardano"]) },
            dependencies: { $0.dashboardSettings.removeWatchlistID = { id in removed.withLock { $0.append(id) } } })
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()
        #expect(store.state.portfolio.settings.watchlistIDs == ["cardano"])

        await store.send(.portfolio(.watchlistRemoved("cardano")))
        await Self.settle(store)
        #expect(removed.withLock { $0 } == ["cardano"])
        #expect(store.state.portfolio.settings.watchlistIDs == ["cardano"], "the state follows the settings, not the action")

        settings.continuation.yield(.defaults)
        await Self.settle(store)
        await task.cancel()

        #expect(store.state.portfolio.settings.watchlistIDs.isEmpty)
        #expect(store.state.portfolio.valued?.pricePollingIDs.contains("cardano") == false)
        #expect(counts.valuations == 1)
        #expect(counts.builds == 0)
    }

    /// Two edits sent back to back on the real client, over a suite of its own. Each runs in its own
    /// effect, so they may persist in either order, and the first echo may already hold both coins.
    /// Whatever the order, both persist, and every echo holds every coin an earlier one held (the
    /// state never reverts), the last holding both.
    @Test func `two quick adds both persist and the state never reverts`() async throws {
        let suiteName = "PortfolioFeatureTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = DashboardSettingsClient.live(defaults: defaults)
        let counts = Counts()
        let log = ActionLog()
        let store = Self.store(
            counts: counts,
            projection: Self.projection,
            built: Self.projection,
            log: log,
            dependencies: { $0.dashboardSettings = client })
        store.exhaustivity = .off(showSkippedAssertions: false)
        let task = await Self.launched(store)
        counts.reset()
        let both: Set = ["cardano", "polkadot"]

        await store.send(.portfolio(.watchlistAdded("cardano")))
        await store.send(.portfolio(.watchlistAdded("polkadot")))
        let deadline = ContinuousClock.now + .seconds(5)
        while log.watchlists.last.map(Set.init) != both, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        await Self.settle(store)
        await task.cancel()

        let echoes = log.watchlists.map(Set.init)
        let persisted = Set(OverviewWatchlistStore.decode(defaults.string(forKey: OverviewWatchlistStore.key) ?? "[]"))
        #expect(persisted == both)
        #expect(echoes.last == both, "\(echoes)")
        #expect(echoes.allSatisfy { !$0.isEmpty && $0.isSubset(of: both) }, "\(echoes)")
        #expect(zip(echoes, echoes.dropFirst()).allSatisfy { $0.isSubset(of: $1) }, "an echo dropped a coin an earlier one held: \(echoes)")
        #expect(Set(store.state.portfolio.settings.watchlistIDs) == both)
        #expect(counts.valuations == echoes.count, "one revaluation per distinct echo")
        #expect(Set(store.state.portfolio.valued?.pricePollingIDs.suffix(2) ?? []) == both)
    }
}
