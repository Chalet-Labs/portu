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
        #expect(changed.withLock { $0 } == false, "the slice re-rendered without a changed output")

        var moved = Self.valued
        moved.headline = OverviewHeadline(total: 6200, change24h: 1300, changePercentage: nil)
        store.send(.portfolio(.revalued(moved)))
        #expect(changed.withLock { $0 } == true, "a changed output must re-render the slice")
    }

    // MARK: - S2

    @Test func `overview polls the read model's ids and stops when the set empties`() async throws {
        let store = Self.appStore()
        let polled = try #require(store.portfolio.valued?.pricePollingIDs)
        let view = ViewRenderSmokeTests().render(OverviewPricePollingDriver(store: store), size: CGSize(width: 10, height: 10))

        try await Self.wait(redrawing: view) { !store.pricePollingIDs.isEmpty }
        #expect(Set(store.pricePollingIDs) == Set(polled))
        let started = store.pricePollingIDs

        // A revaluation that only re-ranks the same IDs keeps the same poll.
        var reranked = try #require(store.portfolio.valued)
        reranked.pricePollingIDs.reverse()
        store.send(.portfolio(.revalued(reranked)))
        try await Self.wait(redrawing: view) { store.portfolio.valued == reranked }
        #expect(store.pricePollingIDs == started, "the same set never restarts the poll")
        #expect(store.connectionStatus == .fetching)

        // An empty set stops it.
        var empty = reranked
        empty.pricePollingIDs = []
        store.send(.portfolio(.revalued(empty)))
        try await Self.wait(redrawing: view) { store.pricePollingIDs.isEmpty }
        #expect(store.connectionStatus == .idle)
    }

    @Test func `overview polls nothing before the first build`() async throws {
        let fetches = FetchCounter()
        let store = Self.appStore(fetches: fetches, built: false)
        ViewRenderSmokeTests().render(OverviewPricePollingDriver(store: store), size: CGSize(width: 10, height: 10))

        try await Task.sleep(for: .milliseconds(300))

        #expect(store.pricePollingIDs.isEmpty)
        #expect(fetches.total == 0)
    }

    // MARK: - Harness

    private final class FetchCounter: Sendable {
        private let fetches = Mutex(0)

        var total: Int {
            fetches.withLock { $0 }
        }

        func fetched() {
            fetches.withLock { $0 += 1 }
        }
    }

    /// The valuation fixture's prices and, once `built`, its projection with the output those prices
    /// value it at. A fetch never returns, so no tick revalues over the outputs a test sends: the
    /// only polling activity is what the driver starts and stops.
    private static func appStore(
        valued override: PortfolioValuedOutput? = nil,
        fetches: FetchCounter = FetchCounter(),
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
            AppFeature()
        } withDependencies: {
            $0.priceService.fetchPrices = { _ in
                fetches.fetched()
                try await Task.sleep(for: .seconds(3600))
                return PriceUpdate(prices: [:], changes24h: [:])
            }
            $0.continuousClock = TestClock()
            $0.currentDate.now = { Fixture.noon(0) }
        }
    }

    /// Yields the main actor until `condition` holds, laying `view` out again each turn: an
    /// offscreen hosting view re-evaluates its body only when it is laid out.
    private static func wait(redrawing view: NSView, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}
