import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// Which saves reload Performance, and what the screen keeps showing while they do.
@MainActor
struct PerformanceFeatureSaveHandlingTests {
    private static let readEntity = "AssetSnapshot"
    private static let unreadEntity = "ProviderPnLSnapshot"

    private func makeStore(
        initialState: PerformanceFeature.State = PerformanceFeature.State(),
        clock: TestClock<Duration> = TestClock(),
        saves: AsyncStream<ModelSaveEvent> = AsyncStream { $0.finish() }) -> TestStoreOf<PerformanceFeature> {
        TestStore(initialState: initialState) {
            PerformanceFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.modelSave.saves = { saves }
        }
    }

    // MARK: - Save observation

    @Test func `a save touching a read entity invalidates the data after the debounce`() async {
        let clock = TestClock()
        let (saves, feed) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let store = makeStore(clock: clock, saves: saves)

        await store.send(.screenEntered)
        feed.yield(.entities([Self.readEntity]))
        await store.receive(\.modelSaved)
        await clock.advance(by: .milliseconds(300))
        await store.receive(\.dataInvalidated) {
            $0.dataRevision = 1
        }

        await store.send(.screenExited)
        await store.finish()
    }

    @Test func `a save touching only entities Performance does not read sends no invalidation`() async {
        let clock = TestClock()
        let (saves, feed) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let store = makeStore(clock: clock, saves: saves)

        await store.send(.screenEntered)
        feed.yield(.entities([Self.unreadEntity]))
        await store.receive(\.modelSaved)
        await clock.advance(by: .seconds(1))

        // The store fails the test if `dataInvalidated` arrived without being asserted.
        await store.send(.screenExited)
        await store.finish()
    }

    @Test func `a save that cannot be scoped always invalidates the data`() async {
        let clock = TestClock()
        let (saves, feed) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let store = makeStore(clock: clock, saves: saves)

        await store.send(.screenEntered)
        feed.yield(.all)
        await store.receive(\.modelSaved)
        await clock.advance(by: .milliseconds(300))
        await store.receive(\.dataInvalidated) {
            $0.dataRevision = 1
        }

        await store.send(.screenExited)
        await store.finish()
    }

    @Test func `a burst of saves collapses into one invalidation after the last one`() async {
        let clock = TestClock()
        let (saves, feed) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let store = makeStore(clock: clock, saves: saves)

        await store.send(.screenEntered)
        feed.yield(.entities([Self.readEntity]))
        await store.receive(\.modelSaved)
        await clock.advance(by: .milliseconds(299))
        feed.yield(.entities([Self.readEntity]))
        await store.receive(\.modelSaved)
        await clock.advance(by: .milliseconds(299))
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.dataInvalidated) {
            $0.dataRevision = 1
        }

        await store.send(.screenExited)
        await store.finish()
    }

    @Test func `leaving the screen cancels the observation and a pending invalidation`() async {
        let clock = TestClock()
        let (saves, feed) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let store = makeStore(clock: clock, saves: saves)

        await store.send(.screenEntered)
        feed.yield(.entities([Self.readEntity]))
        await store.receive(\.modelSaved)
        await store.send(.screenExited)

        feed.yield(.entities([Self.readEntity]))
        await clock.advance(by: .seconds(1))
        await store.finish()
    }

    @Test func `entering the screen again keeps a pending invalidation`() async {
        let clock = TestClock()
        let (first, firstFeed) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let (second, _) = AsyncStream.makeStream(of: ModelSaveEvent.self)
        let streams = Mutex([first, second])
        let store = TestStore(initialState: PerformanceFeature.State()) {
            PerformanceFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.modelSave.saves = { streams.withLock { $0.removeFirst() } }
        }

        await store.send(.screenEntered)
        firstFeed.yield(.entities([Self.readEntity]))
        await store.receive(\.modelSaved)
        await clock.advance(by: .milliseconds(100))
        await store.send(.screenEntered)
        await clock.advance(by: .milliseconds(200))
        await store.receive(\.dataInvalidated) {
            $0.dataRevision = 1
        }

        await store.send(.screenExited)
        await store.finish()
    }

    // MARK: - Reload keeps what is on screen

    private static let previous = PerformanceDataSnapshot(
        categories: [
            PortfolioCategorySnapshot(
                id: UUID(),
                name: "Major",
                sortOrder: 0,
                semanticRole: .normal,
                isSystemRequired: false)
        ],
        valueChart: PerformanceValueChartData(providerDisclosure: "Provider history"),
        bottomPanel: PerformanceBottomPanelData(categoryChanges: [
            CategoryChange(id: "major", name: "Major", startValue: 100, endValue: 110, percentChange: 10)
        ]))

    private func stateShowing(_ snapshot: PerformanceDataSnapshot) -> PerformanceFeature.State {
        var state = PerformanceFeature.State()
        state.categories = snapshot.categories
        state.categoryChart = snapshot.categoryChart
        state.valueChartData = snapshot.valueChart
        state.bottomPanelData = snapshot.bottomPanel
        return state
    }

    @Test func `a reload keeps the previous data until its response arrives`() async {
        let (gate, release) = AsyncStream<Void>.makeStream()
        let next = PerformanceDataSnapshot(
            valueChart: PerformanceValueChartData(providerDisclosure: "Refreshed history"))
        let store = TestStore(initialState: stateShowing(Self.previous)) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in
                for await _ in gate {
                    break
                }
                return next
            }
        }

        await store.send(.dataRequested(PerformanceDataRequest(startDate: Date(timeIntervalSince1970: 0)))) {
            $0.dataRequestGeneration = 1
            $0.activeDataRequestID = "performance-data|1"
            $0.isDataLoading = true
        }
        #expect(store.state.valueChartData == Self.previous.valueChart)
        #expect(store.state.bottomPanelData == Self.previous.bottomPanel)
        #expect(store.state.categories == Self.previous.categories)

        release.yield()
        await store.receive(\.dataResponse) {
            $0.isDataLoading = false
            $0.categories = next.categories
            $0.valueChartData = next.valueChart
            $0.bottomPanelData = next.bottomPanel
        }
    }

    @Test func `a failed reload keeps the previous data and reports the error`() async {
        let store = TestStore(initialState: stateShowing(Self.previous)) {
            PerformanceFeature()
        } withDependencies: {
            $0.performanceData.load = { _ in
                throw PerformanceDataClientError(message: "Store unavailable")
            }
        }

        await store.send(.dataRequested(PerformanceDataRequest(startDate: Date(timeIntervalSince1970: 0)))) {
            $0.dataRequestGeneration = 1
            $0.activeDataRequestID = "performance-data|1"
            $0.isDataLoading = true
        }
        await store.receive(\.dataResponse) {
            $0.isDataLoading = false
            $0.dataLoadError = "Store unavailable"
        }

        #expect(store.state.valueChartData == Self.previous.valueChart)
        #expect(store.state.bottomPanelData == Self.previous.bottomPanel)
    }
}
