import AppKit
import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Synchronization
import Testing

/// The portfolio slice of the dashboard (the Sidebar header and the Overview top bar) rendered over
/// the in-memory store and read back as text, so the migration to the portfolio read model (#123)
/// keeps every formatted value byte-identical. The store shows EUR at 0.9 with the seeded
/// portfolio priced live: 2 ETH at 3050 (+2.1 % live), 4000 USDC supplied at 1 and 500 borrowed,
/// so net 9600 USD → € 8,640, 24h change 6100 × 0.021 / 1.021 → € 113, and 1.32 %.
///
/// The literals were captured from the pre-migration views on master; each sequence is the labels
/// one view exposes, in tree order, from one 1400×900 pass.
extension ViewRenderSmokeTests {
    private static let sidebarHeaderLabels = ["P", "€ 8,640", "€ 113", "24h", "1.32%"]
    private static let topBarLabels = [
        "€ 8,640", "€ 113", "EUR change 24h", "Triangle Arrow Up", "1.32%", "% change 24h"
    ]

    /// The projection builds off the main actor, so the test yields with `Task.sleep` while it waits:
    /// spinning the run loop from a synchronous test never lets the build's result back onto it.
    @Test(.renderedTextReadable) func `the portfolio slice shows the headline in the display currency`() async throws {
        let container = try makeContainer()
        let store = Self.sliceStore(projector: .live(modelContainer: container))
        let appState = AppState()
        appState.bridge(from: store)

        let hostingView = render(
            ContentView(store: store)
                .modelContainer(container)
                .environment(appState)
                .frame(width: 1400, height: 900),
            size: CGSize(width: 1400, height: 900))

        var texts = Self.accessibilityLabels(hostingView)
        let deadline = Date().addingTimeInterval(10)
        while
            !Self.shows(texts: texts, labels: Self.sidebarHeaderLabels)
            || !Self.shows(texts: texts, labels: Self.topBarLabels), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            texts = Self.accessibilityLabels(hostingView)
        }
        #expect(Self.shows(texts: texts, labels: Self.sidebarHeaderLabels), "header sequence missing in \(texts)")
        #expect(Self.shows(texts: texts, labels: Self.topBarLabels), "top bar sequence missing in \(texts)")
    }

    /// Before the first build lands there is nothing to value: both views show a dash for each figure,
    /// while the build the window started is still running.
    @Test(.renderedTextReadable) func `the portfolio slice shows dashes until the first build`() async throws {
        let container = try makeContainer()
        let started = Mutex(false)
        let store = Self.sliceStore(projector: PortfolioProjectorClient { _ in
            started.withLock { $0 = true }
            try await Task.sleep(for: .seconds(3600))
            return .empty
        })
        let appState = AppState()
        appState.bridge(from: store)

        let hostingView = render(
            ContentView(store: store)
                .modelContainer(container)
                .environment(appState)
                .frame(width: 1400, height: 900),
            size: CGSize(width: 1400, height: 900))
        let deadline = Date().addingTimeInterval(10)
        while !started.withLock({ $0 }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(started.withLock { $0 }, "the window never started a build")
        try await Task.sleep(for: .milliseconds(100))
        let texts = Self.accessibilityLabels(hostingView)

        #expect(Self.shows(texts: texts, labels: ["P", "—", "—", "24h", "—"]), "\(texts)")
        #expect(Self.shows(texts: texts, labels: ["—", "—", "change 24h", "—", "% change 24h"]), "\(texts)")
        #expect(store.portfolio.valued == nil)
    }

    /// A failed first build says so on the dashed total of both views; the launch transient's
    /// dashes and a shown total carry no tooltip, even with an older failure recorded.
    @Test(.renderedTextReadable) func `the dashed slice carries a failed build's error`() {
        let failed = sliceHelp(valued: nil, buildError: "store unavailable")
        let loading = sliceHelp(valued: nil, buildError: nil)
        let shown = sliceHelp(
            valued: PortfolioValuedOutput(
                headline: OverviewHeadline(total: 10, change24h: 1, changePercentage: nil),
                currencyCode: "USD",
                pricePollingIDs: []),
            buildError: "store unavailable")

        #expect(failed == ["Portfolio unavailable: store unavailable", "Portfolio unavailable: store unavailable"])
        #expect(loading == [nil, nil])
        #expect(shown == [nil, nil])
    }

    /// The tooltip of the Sidebar header and of the top bar over a portfolio store in this state.
    private func sliceHelp(valued: PortfolioValuedOutput?, buildError: String?) -> [String?] {
        var state = PortfolioFeature.State()
        state.valued = valued
        state.buildError = buildError
        let store = StoreOf<PortfolioFeature>(initialState: state) { PortfolioFeature() }
        return [
            Self.helpText(render(SidebarPortfolioHeader(store: store), size: CGSize(width: 260, height: 80))),
            Self.helpText(render(OverviewTopBar(store: store), size: CGSize(width: 260, height: 160)))
        ]
    }

    /// Whether `labels` appear in `texts` as one contiguous run, the order the view exposes them in.
    private static func shows(texts: [String], labels: [String]) -> Bool {
        guard !labels.isEmpty, labels.count <= texts.count else { return false }
        return (0 ... texts.count - labels.count).contains { start in
            texts[start ..< start + labels.count] == labels[...]
        }
    }

    /// The dashboard store for the slice: EUR at 0.9 with the seeded portfolio priced live. The Overview
    /// panels' specs also give it a chart projector, the clock the seeded data is dated by, and settings.
    static func sliceStore(
        projector: PortfolioProjectorClient,
        chartProjector: PortfolioValueChartProjectorClient = .testValue,
        now: Date = Date(timeIntervalSince1970: 1_000_000),
        settings: DashboardSettings = .defaults) -> StoreOf<AppFeature> {
        var state = AppFeature.State(selectedSection: .overview)
        state.selectedCurrency = .eur
        state.currentUSDToDisplayRate = PortfolioValuationFixture.decimal("0.9")
        state.livePricesUSD = ["ethereum": 3050, "usd-coin": 1]
        state.priceChanges24h = ["ethereum": 0.021]
        state.lastPriceUpdate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return Store(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { _ in SyncResult(failedAccounts: []) }
            $0.priceService.fetchPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.invalidateCache = {}
            $0.continuousClock = TestClock()
            $0.currentDate.now = { now }
            $0.portfolioProjector = projector
            $0.portfolioValueChartProjector = chartProjector
            $0.dashboardSettings.current = { settings }
        }
    }
}
