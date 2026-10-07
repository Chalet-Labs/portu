import AppKit
import ComposableArchitecture
import Foundation
import Observation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Synchronization
import Testing

/// Hosts the real `PerformanceView` and records the loads it asks for. The view's task identity
/// can't be read from outside, so these tests watch what it causes: which changes reload the
/// data, and which prices a reload carries.
@MainActor
struct PerformanceLoadIdentityTests {
    @Test func `live price updates do not reload the data`() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        #expect(await harness.waitUntil { harness.requests.count == 1 }, "Showing the page loads once")

        harness.store.send(.pricesReceived(PriceUpdate(
            currency: .usd,
            prices: ["ethereum": 3200],
            changes24h: [:])))
        let reloaded = await harness.waitUntil(timeout: .milliseconds(600)) { harness.requests.count > 1 }
        #expect(!reloaded, "A price tick must not restart the load")

        // A real input still reloads, and the reload reads the prices of that moment.
        harness.store.send(.performance(.chartModeChanged(.assets)))
        #expect(await harness.waitUntil { harness.requests.count > 1 }, "A real input must still reload")
        #expect(harness.requests.map(\.chartMode) == [.value, .assets])
        #expect(harness.requests.last?.liveDisplayPrices == ["ethereum": 3200])
    }

    @Test func `historical price updates do not reload the data`() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        #expect(await harness.waitUntil { harness.requests.count == 1 }, "Showing the page loads once")

        harness.historicalPrices.prices = ["bitcoin": 64000]
        let reloaded = await harness.waitUntil(timeout: .milliseconds(600)) { harness.requests.count > 1 }
        #expect(!reloaded, "A historical price refresh must not restart the load")

        harness.store.send(.performance(.chartModeChanged(.assets)))
        #expect(await harness.waitUntil { harness.requests.count > 1 }, "A real input must still reload")
        #expect(harness.requests.map(\.chartMode) == [.value, .assets])
        #expect(harness.requests.last?.historicalDisplayPrices == ["bitcoin": 64000])
    }

    @Test func `a save reloads the page only when it touches what the page reads`() async throws {
        let harness = try Harness(observesSaves: true)
        defer { harness.tearDown() }
        let context = harness.container.mainContext
        #expect(await harness.waitUntil { harness.requests.count == 1 }, "Showing the page loads once")

        context.insert(WalletAddress(address: "0xabc"))
        try context.save()
        let reloaded = await harness.waitUntil(timeout: .milliseconds(900), advancingClock: true) {
            harness.requests.count > 1
        }
        #expect(!reloaded, "Performance reads no wallet addresses")

        context.insert(PortfolioCategory(name: "Custom", sortOrder: 0))
        try context.save()
        #expect(
            await harness.waitUntil(advancingClock: true) { harness.requests.count > 1 },
            "A save to a model Performance reads must reload the page")
        #expect(harness.requests.count == 2)
    }
}

/// The same hosted page, measured: the status of a load has to change what it shows and never
/// how tall the page is, or everything below it jumps while a sync saves in the background.
@MainActor
struct PerformancePageLayoutTests {
    @Test func `loading and failing to load keep the height of the page`() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        #expect(await harness.waitUntil { harness.requests.count == 1 }, "Showing the page loads once")
        #expect(await harness.waitUntil { !harness.store.performance.isDataLoading })
        let idle = try #require(await harness.pageContentHeight(), "The page content has to be measurable")
        #expect(idle > 0)

        harness.setLoadBehavior(.hold)
        harness.store.send(.performance(.dataInvalidated))
        #expect(await harness.waitUntil { harness.store.performance.isDataLoading })
        #expect(await harness.pageContentHeight() == idle, "A load in flight must not move the page")

        harness.releaseHeldLoad()
        #expect(await harness.waitUntil { !harness.store.performance.isDataLoading })
        #expect(await harness.pageContentHeight() == idle, "A finished load must not move the page")

        harness.setLoadBehavior(.fail)
        harness.store.send(.performance(.dataInvalidated))
        #expect(await harness.waitUntil { harness.store.performance.dataLoadError != nil })
        #expect(await harness.pageContentHeight() == idle, "A failed load must not move the page")
    }
}

// MARK: - Harness

@MainActor
private final class Harness {
    let store: StoreOf<AppFeature>
    let container: ModelContainer
    let historicalPrices = HistoricalPrices()
    private let clock = TestClock<Duration>()
    private let log = RequestLog()
    private let loads = LoadControl()
    private let contentView: NSView
    private let window: NSWindow

    var requests: [PerformanceDataRequest] {
        log.requests
    }

    /// `observesSaves` binds the live save client to the hosted container; otherwise the
    /// inert default is used and no save can reach the page.
    init(observesSaves: Bool = false) throws {
        let log = log
        let clock = clock
        let loads = loads
        let container = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        self.container = container
        self.store = Store(initialState: AppFeature.State(selectedSection: .performance)) {
            AppFeature()
        } withDependencies: {
            $0.performanceData.load = { request in
                log.record(request)
                switch loads.behavior {
                case .succeed:
                    return .empty
                case .hold:
                    for await _ in loads.heldLoads {
                        break
                    }
                    return .empty
                case .fail:
                    throw PerformanceDataClientError(message: "Store unavailable")
                }
            }
            if observesSaves {
                $0.modelSave = .live(container: container)
            }
            $0.continuousClock = clock
            $0.currentDate.now = { Date(timeIntervalSince1970: 1_000_000) }
        }

        let appState = AppState()
        appState.bridge(from: store)

        let hostingView = NSHostingView(rootView: PerformanceHost(store: store, historicalPrices: historicalPrices)
            .modelContainer(container)
            .environment(appState)
            .frame(width: 1400, height: 900))
        self.window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = hostingView
        window.orderFrontRegardless()
        self.contentView = hostingView
    }

    func tearDown() {
        window.close()
    }

    func setLoadBehavior(_ newValue: LoadControl.Behavior) {
        loads.behavior = newValue
    }

    func releaseHeldLoad() {
        loads.release()
    }

    /// Height of what the page's scroll view scrolls, measured after SwiftUI has had a few
    /// run-loop turns to lay out the latest state. It is what shifts when a row appears.
    func pageContentHeight() async -> CGFloat? {
        try? await Task.sleep(for: .milliseconds(150))
        contentView.layoutSubtreeIfNeeded()
        return Self.firstScrollView(in: contentView)?.documentView?.frame.height
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
    }

    /// Polls on the main actor so SwiftUI keeps running between checks. With `advancingClock`
    /// each poll also moves the injected clock, because a debounce only starts sleeping a few
    /// run-loop turns after the save that armed it.
    func waitUntil(
        timeout: Duration = .seconds(10),
        advancingClock: Bool = false,
        _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            if advancingClock {
                await clock.advance(by: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}

@MainActor
@Observable
private final class HistoricalPrices {
    var prices: [String: Decimal] = [:]
}

private struct PerformanceHost: View {
    let store: StoreOf<AppFeature>
    let historicalPrices: HistoricalPrices

    var body: some View {
        PerformanceView(store: store)
            .environment(\.historicalDisplayPrices, historicalPrices.prices)
    }
}

/// How the hosted page's loads end: at once, when released, or with an error.
private final class LoadControl: Sendable {
    enum Behavior {
        case succeed
        case hold
        case fail
    }

    private let storage = Mutex<Behavior>(.succeed)
    private let held = AsyncStream<Void>.makeStream()

    var behavior: Behavior {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    var heldLoads: AsyncStream<Void> {
        held.stream
    }

    func release() {
        held.continuation.yield()
    }
}

private final class RequestLog: Sendable {
    private let storage = Mutex<[PerformanceDataRequest]>([])

    var requests: [PerformanceDataRequest] {
        storage.withLock { $0 }
    }

    func record(_ request: PerformanceDataRequest) {
        storage.withLock { $0.append(request) }
    }
}
