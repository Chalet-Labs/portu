import AppKit
import ComposableArchitecture
import Foundation
import Observation
@testable import Portu
import PortuCore
import SwiftUI
import Synchronization
import Testing

/// What re-renders the slice and the Overview panels, and what Overview polls (#123, spec S1 and
/// S2; #124, spec O3).
@MainActor
struct PortfolioSliceBehaviourTests {
    private typealias Fixture = PortfolioValuationFixture

    private static let valued = PortfolioValuedOutput(
        headline: OverviewHeadline(total: 6100, change24h: 1200, changePercentage: Decimal(1200) / Decimal(4900)),
        currencyCode: "USD",
        pricePollingIDs: ["ethereum", "degen-base", "bitcoin"])

    /// The fixture's panels at the fixture's prices.
    private static let revaluation = revaluation(liveChanges24h: Fixture.liveChanges24h)

    private static func revaluation(
        liveChanges24h: [String: Decimal],
        currency: FiatCurrency = .usd,
        rate: Decimal = 1) -> PortfolioRevaluation {
        PortfolioValuator.compute(PortfolioValuationRequest(
            projection: .fixture(historical: Fixture.historical),
            prices: PortfolioPriceInputs(
                livePricesUSD: Fixture.livePricesUSD,
                liveChanges24h: liveChanges24h,
                usdToDisplayRate: rate,
                currency: currency),
            settings: .defaults))
    }

    private static func revalued(_ valued: PortfolioValuedOutput) -> PortfolioFeature.Action {
        .revalued(PortfolioRevaluation(valued: valued, overview: revaluation.overview))
    }

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
        store.send(.portfolio(Self.revalued(Self.valued)))
        // A rebuild that fails under a shown total changes only `buildError`, which is read only
        // while the totals are dashed.
        store.send(.portfolio(.projectionBuildFailed("store unavailable")))
        #expect(changed.withLock { $0 } == false, "the slice re-rendered without a changed output")

        var moved = Self.valued
        moved.headline = OverviewHeadline(total: 6200, change24h: 1300, changePercentage: nil)
        store.send(.portfolio(Self.revalued(moved)))
        #expect(changed.withLock { $0 } == true, "a changed output must re-render the slice")
    }

    // MARK: - O3: each panel re-renders only for its own output

    private enum Panel: CaseIterable {
        case cards, tabs, donut, health, watchlist, chart, header
    }

    /// Whether anything a panel read under observation has changed since.
    private final class Changed: Sendable {
        private let flag = Mutex(false)

        var value: Bool {
            flag.withLock { $0 }
        }

        func set() {
            flag.withLock { $0 = true }
        }
    }

    /// Reads one panel's body under observation.
    private static func tracking(_ panel: Panel, in store: StoreOf<AppFeature>) -> Changed {
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)
        let changed = Changed()
        withObservationTracking {
            switch panel {
            case .cards: _ = OverviewSummaryCards(store: portfolio).body
            case .tabs: _ = OverviewPositionTabs(store: portfolio).body
            case .donut: _ = TopAssetsDonut(store: store).body
            case .health: _ = PortfolioHealthPanel(store: store).body
            case .watchlist: _ = PriceWatchlist(store: store).body
            case .chart: _ = PortfolioValueChart(store: portfolio).body
            case .header:
                _ = SidebarPortfolioHeader(store: portfolio).body
                _ = OverviewTopBar(store: portfolio).body
            }
        } onChange: {
            changed.set()
        }
        return changed
    }

    /// Reads one panel's body under observation, then reports whether `act` notified it.
    private static func notified(_ panel: Panel, in store: StoreOf<AppFeature>, by act: () -> Void) -> Bool {
        let changed = tracking(panel, in: store)
        act()
        return changed.value
    }

    /// As `notified`, for an action whose effects land later: waits until a revaluation and a
    /// conversion have, which a rate or currency change starts together.
    private static func notified(
        _ panel: Panel,
        in store: StoreOf<AppFeature>,
        landed: Landed,
        by act: () -> Void) async throws -> Bool {
        let changed = tracking(panel, in: store)
        act()
        let deadline = Date().addingTimeInterval(5)
        while landed.revaluations == 0 || landed.conversions == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(landed.revaluations == 1 && landed.conversions == 1, "\(panel): the rate change's effects never landed")
        return changed.value
    }

    /// A failed rebuild of the holdings or of the chart, while both show, notifies no panel: neither
    /// error is read until a panel is dashed.
    @Test func `a navigation click or a failed rebuild re-renders no panel`() {
        for panel in Panel.allCases {
            let store = Self.appStore()
            #expect(!Self.notified(panel, in: store) {
                store.send(.sectionSelected(.exposure))
                store.send(.sectionSelected(.overview))
                store.send(.portfolio(.projectionBuildFailed("store unavailable")))
                store.send(.portfolio(.valueChartBuildFailed("chart store unavailable")))
            }, "\(panel)")
        }
    }

    /// The chart's build error is its own field, read only by the dashed chart: when the first chart
    /// build fails, that chart re-renders to carry it, and no other panel does, nor the headline.
    @Test func `a failed first chart build re-renders only the dashed chart`() {
        for panel in Panel.allCases {
            let store = Self.appStore(built: false)
            let notifies = Self.notified(panel, in: store) { store.send(.portfolio(.valueChartBuildFailed("chart store unavailable"))) }

            #expect(notifies == (panel == .chart), "\(panel)")
        }
    }

    /// Each output is its own observed field: with the headline equal, outputs that move re-render
    /// the panels that read them, and no headline reader, other panel or chart.
    @Test func `a revaluation with an equal headline re-renders only the panels whose output moved`() {
        let noHealth = PortfolioHealthFeature.health(Fixture.context(inputs: []))
        let scenarios: [(panels: Set<Panel>, move: (inout OverviewValuedOutput) -> Void)] = [
            ([.cards], { $0.summaryCards = [] }),
            ([.tabs], { $0.positionTabs = [:] }),
            ([.donut], { $0.topAssets = [:] }),
            ([.health], { $0.health = noHealth }),
            ([.watchlist], { $0.watchlistRows = [] }),
            ([.cards, .health], {
                $0.summaryCards = []
                $0.health = noHealth
            })
        ]

        for scenario in scenarios {
            var moved = Self.revaluation
            scenario.move(&moved.overview)
            #expect(moved.valued == Self.revaluation.valued, "the headline is equal")
            #expect(moved.overview != Self.revaluation.overview)
            for panel in Panel.allCases {
                let store = Self.appStore()
                let notifies = Self.notified(panel, in: store) { store.send(.portfolio(.revalued(moved))) }

                #expect(notifies == scenario.panels.contains(panel), "\(scenario.panels) moved, \(panel)")
            }
        }
    }

    /// The cards, the donut and health show no 24h figure, so a change of the fractions alone
    /// leaves them, and the chart, alone.
    @Test func `a change to the live fractions alone re-renders only the panels that show one`() {
        var fractions = Fixture.liveChanges24h
        for key in fractions.keys {
            fractions[key] = -(fractions[key] ?? 0)
        }
        let flipped = Self.revaluation(liveChanges24h: fractions)
        let expected: [Panel: Bool] = [
            .cards: false, .donut: false, .health: false, .chart: false,
            .tabs: true, .watchlist: true, .header: true
        ]

        for (panel, notifies) in expected {
            let store = Self.appStore()
            #expect(Self.notified(panel, in: store) { store.send(.portfolio(.revalued(flipped))) } == notifies, "\(panel)")
        }
    }

    /// A converted chart re-renders the chart and nothing else; an equal one re-renders nothing.
    @Test func `only a changed chart re-renders the chart`() throws {
        let store = Self.appStore()
        let chart = try #require(store.portfolio.valueChart)
        #expect(!Self.notified(.chart, in: store) { store.send(.portfolio(.valueChartConverted(chart))) })

        var moved = chart
        moved.currencyCode = "EUR"
        #expect(Self.notified(.chart, in: store) { store.send(.portfolio(.valueChartConverted(moved))) })
        for panel in Panel.allCases where panel != .chart {
            let store = Self.appStore()
            #expect(!Self.notified(panel, in: store) { store.send(.portfolio(.valueChartConverted(moved))) }, "\(panel)")
        }
    }

    /// The periodic refresh sends the rate the dashboard already has: the panels are revalued and the
    /// chart converted again, nothing differs, and nothing re-renders.
    @Test func `an equal rate refresh re-renders no panel`() async throws {
        let rate = Fixture.decimal("0.95")
        for panel in Panel.allCases {
            let landed = Landed()
            let store = Self.appStore(currency: .eur, rate: rate, landed: landed)
            let changed = try await Self.notified(panel, in: store, landed: landed) {
                store.send(.currentCurrencyConversionRateReceived(.eur, .success(rate)))
            }
            #expect(!changed, "\(panel)")
        }
    }

    /// A new rate moves every money figure, so every panel re-renders: the headline, the cards, the
    /// tabs, the donut, health, the watchlist and the chart.
    @Test func `a changed rate re-renders every panel that shows money`() async throws {
        let refreshed = Fixture.decimal("0.96")
        for panel in Panel.allCases {
            let landed = Landed()
            let store = Self.appStore(currency: .eur, rate: Fixture.decimal("0.95"), landed: landed)
            let changed = try await Self.notified(panel, in: store, landed: landed) {
                store.send(.currentCurrencyConversionRateReceived(.eur, .success(refreshed)))
            }
            #expect(changed, "\(panel)")
        }
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
        store.send(.portfolio(Self.revalued(reranked)))
        try await Self.redraw(view)
        #expect(starts.total == 1, "the driver restarted polling for the same set")

        // A different set restarts it.
        var widened = reranked
        widened.pricePollingIDs.append("cardano")
        store.send(.portfolio(Self.revalued(widened)))
        try await Self.wait(redrawing: view) { starts.total == 2 }
        #expect(store.pricePollingIDs.contains("cardano"))

        // An empty set stops it.
        var empty = widened
        empty.pricePollingIDs = []
        store.send(.portfolio(Self.revalued(empty)))
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
        store.send(.portfolio(Self.revalued(PortfolioValuedOutput(
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

    /// Counts the revaluations and conversions that land.
    private final class Landed: Sendable {
        private let counts = Mutex((revaluations: 0, conversions: 0))

        var revaluations: Int {
            counts.withLock { $0.revaluations }
        }

        var conversions: Int {
            counts.withLock { $0.conversions }
        }

        func record(_ action: AppFeature.Action) {
            counts.withLock {
                if action.is(\.portfolio.revalued) {
                    $0.revaluations += 1
                }
                if action.is(\.portfolio.valueChartConverted) {
                    $0.conversions += 1
                }
            }
        }
    }

    /// The valuation fixture's prices and, once `built`, its projection with the output those prices
    /// value it at, and a converted chart, in `currency` at `rate`. A fetch never returns, so no tick
    /// revalues over the outputs a test sends: the only polling activity is what the driver starts
    /// and stops. `starts` counts every `startPricePolling` the driver sends, `landed` every
    /// revaluation and conversion.
    private static func appStore(
        valued override: PortfolioValuedOutput? = nil,
        starts: StartCounter = StartCounter(),
        built: Bool = true,
        currency: FiatCurrency = .usd,
        rate: Decimal = 1,
        landed: Landed = Landed()) -> StoreOf<AppFeature> {
        var state = AppFeature.State()
        state.selectedCurrency = currency
        state.currentUSDToDisplayRate = rate
        // Today's historical FX is already fetched, so a rate refresh starts no top-up.
        state.historicalFXLastRefreshDayByCurrency[currency] = HistoricalPriceCalendar.utcStartOfDay(for: Fixture.noon(0))
        state.livePricesUSD = Fixture.livePricesUSD
        state.priceChanges24h = Fixture.liveChanges24h
        if built {
            let panels = revaluation(liveChanges24h: Fixture.liveChanges24h, currency: currency, rate: rate)
            state.portfolio.projection = PortfolioProjection.fixture(historical: Fixture.historical)
            state.portfolio.valued = override ?? panels.valued
            state.portfolio.overview.update(with: panels.overview)
            let source = PortfolioValueChartSource(
                snapshots: [PortfolioValueSnapshotPoint(id: Fixture.uuid(7001), timestamp: Fixture.noon(-1), totalValueUSD: 10000, isPartial: false)],
                rates: [],
                estimatedUSD: [])
            state.portfolio.valueChartSource = source
            state.portfolio.valueChart = PortfolioValueChartData.converting(
                source,
                currency: currency,
                usdToDisplayRate: rate,
                today: Fixture.noon(0))
        }
        return Store(initialState: state) {
            Reduce { _, action in
                if case .startPricePolling = action {
                    starts.started()
                }
                landed.record(action)
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
