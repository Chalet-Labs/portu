import AppKit
import ComposableArchitecture
import Foundation
import Observation
@testable import Portu
import PortuCore
import SwiftUI
import Synchronization
import Testing

/// What re-renders the slice and what it polls (#123, spec S1 and S2).
@MainActor
struct PortfolioSliceBehaviourTests {
    private typealias Fixture = PortfolioValuationFixture

    private static let valued = PortfolioValuedOutput(
        headline: OverviewHeadline(total: 6100, change24h: 1200, changePercentage: Decimal(1200) / Decimal(4900)),
        currencyCode: "USD",
        pricePollingIDs: ["ethereum", "degen-base", "bitcoin"])

    // MARK: - S1

    /// The slice views read only the read model's output: a navigation click and a revaluation with
    /// an equal result notify neither; a changed result does.
    @Test func `only a changed valued output re-renders the slice`() {
        let store = Self.appStore(valued: Self.valued)
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)
        let changed = Mutex(false)
        let track = {
            withObservationTracking {
                _ = SidebarPortfolioHeader(store: portfolio).body
                _ = OverviewTopBar(store: portfolio).body
            } onChange: {
                changed.withLock { $0 = true }
            }
        }

        track()
        store.send(.sectionSelected(.exposure))
        store.send(.portfolio(.revalued(Self.valued)))
        // A rebuild that fails under a shown total changes only `buildError`, which is read only
        // while the totals are dashed.
        store.send(.portfolio(.projectionBuildFailed("store unavailable")))
        #expect(changed.withLock { $0 } == false, "the slice re-rendered without a changed output")

        var moved = Self.valued
        moved.headline = OverviewHeadline(total: 6200, change24h: 1300, changePercentage: nil)
        store.send(.portfolio(.revalued(moved)))
        #expect(changed.withLock { $0 } == true, "a changed output must re-render the slice")
    }

    // MARK: - S2

    @Test func `overview polls the read model's ids and restarts only when the set changes`() async throws {
        let starts = StartCounter()
        let store = Self.appStore(starts: starts)
        let polled = try #require(store.portfolio.valued?.pricePollingIDs)
        let view = ViewRenderSmokeTests().render(OverviewPricePollingDriver(store: store), size: CGSize(width: 10, height: 10))

        try await Self.wait(redrawing: view) { !store.pricePollingIDs.isEmpty }
        #expect(Set(store.pricePollingIDs) == Set(polled))
        #expect(starts.total == 1)

        // A revaluation that only re-ranks the same IDs sends no new start.
        var reranked = try #require(store.portfolio.valued)
        reranked.pricePollingIDs.reverse()
        store.send(.portfolio(.revalued(reranked)))
        try await Self.redraw(view)
        #expect(starts.total == 1, "the driver restarted polling for the same set")

        // A different set restarts it.
        var widened = reranked
        widened.pricePollingIDs.append("cardano")
        store.send(.portfolio(.revalued(widened)))
        try await Self.wait(redrawing: view) { starts.total == 2 }
        #expect(store.pricePollingIDs.contains("cardano"))

        // An empty set stops it.
        var empty = widened
        empty.pricePollingIDs = []
        store.send(.portfolio(.revalued(empty)))
        try await Self.wait(redrawing: view) { store.pricePollingIDs.isEmpty }
        #expect(store.connectionStatus == .idle)
    }

    @Test func `overview polls nothing before the first build, then the first ids`() async throws {
        let starts = StartCounter()
        let store = Self.appStore(starts: starts, built: false)
        let view = ViewRenderSmokeTests().render(OverviewPricePollingDriver(store: store), size: CGSize(width: 10, height: 10))

        try await Self.redraw(view)
        #expect(starts.total == 0)
        #expect(store.pricePollingIDs.isEmpty)

        // The first valued output starts polling: the driver was running and waiting.
        store.send(.portfolio(.revalued(PortfolioValuedOutput(
            headline: OverviewHeadline(total: 1, change24h: 0, changePercentage: nil),
            currencyCode: "USD",
            pricePollingIDs: ["ethereum"]))))
        try await Self.wait(redrawing: view) { starts.total == 1 }
        #expect(store.pricePollingIDs == ["ethereum"])
    }

    // MARK: - Harness

    private final class StartCounter: Sendable {
        private let starts = Mutex(0)

        var total: Int {
            starts.withLock { $0 }
        }

        func started() {
            starts.withLock { $0 += 1 }
        }
    }

    /// The valuation fixture's prices and, once `built`, its projection with the output those prices
    /// value it at. A fetch never returns, so no tick revalues over the outputs a test sends: the
    /// only polling activity is what the driver starts and stops. `starts` counts every
    /// `startPricePolling` the driver sends.
    private static func appStore(
        valued override: PortfolioValuedOutput? = nil,
        starts: StartCounter = StartCounter(),
        built: Bool = true) -> StoreOf<AppFeature> {
        var state = AppFeature.State()
        state.livePricesUSD = Fixture.livePricesUSD
        state.priceChanges24h = Fixture.liveChanges24h
        if built {
            let projection = PortfolioProjection.fixture()
            state.portfolio.projection = projection
            state.portfolio.valued = override ?? PortfolioValuator.compute(PortfolioValuationRequest(
                projection: projection,
                prices: state.portfolioPriceInputs,
                settings: state.portfolio.settings))
        }
        return Store(initialState: state) {
            Reduce { _, action in
                if case .startPricePolling = action {
                    starts.started()
                }
                return .none
            }
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in
                try await Task.sleep(for: .seconds(3600))
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.continuousClock = TestClock()
            $0.currentDate.now = { Fixture.noon(0) }
        }
    }

    /// Lays an offscreen hosting view out again: it re-evaluates its body only when laid out.
    private static func layOut(_ view: NSView) {
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    /// Several layout turns with the main actor yielded between them, so any task the driver would
    /// start has run.
    private static func redraw(_ view: NSView, turns: Int = 15) async throws {
        for _ in 0 ..< turns {
            layOut(view)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Yields the main actor until `condition` holds, laying `view` out again each turn.
    private static func wait(redrawing view: NSView, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            layOut(view)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}
