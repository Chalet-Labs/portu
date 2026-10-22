import AppKit
import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The Overview panels rendered from the portfolio read model and read back as text (#124, spec O4
/// and C4): their values after a build, a dash before the first one, and today's empty text after a
/// build with nothing to show. The store shows EUR at 0.9 with the seeded portfolio priced live:
/// 2 ETH at 3050 (+2.1 % live) idle, and 4000 USDC supplied against 500 borrowed, so Idle holds
/// € 5,490, Deployed € 3,600 and Debt € 450.
extension ViewRenderSmokeTests {
    private static let rate = PortfolioValuationFixture.decimal("0.9")
    /// The seeded data is dated up to this day.
    private static let seededNow = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let estimateCaption = "Dashed segment is estimated from earliest Portu holdings and cached historical prices."

    // MARK: - After a build

    @Test(.renderedTextReadable) func `the overview panels show their values after a build`() async throws {
        let container = try makeContainer()
        let store = Self.overviewStore(over: container)
        try await Self.built(store)
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)
        let eur = { (usd: Decimal) in OverviewPriceDisplay.currency(usd * Self.rate, currencyCode: "EUR") }
        let majors = OverviewSummaryLabels.majorCategoryTitle(categories: PortfolioCategoryResolver.defaults.categories)

        let cards = try OverviewModelWiringTests.texts(of: OverviewSummaryCards(store: portfolio), size: CGSize(width: 1200, height: 300))
        let tabs = try OverviewModelWiringTests.texts(of: OverviewPositionTabs(store: portfolio), size: CGSize(width: 1000, height: 500))
        let borrowing = try OverviewModelWiringTests.texts(
            of: OverviewPositionTabs(store: portfolio),
            size: CGSize(width: 1000, height: 500),
            pressing: OverviewPositionTab.borrowing.rawValue)
        let donut = try OverviewModelWiringTests.texts(of: TopAssetsDonut(store: store), size: CGSize(width: 600, height: 400))
        let health = try OverviewModelWiringTests.texts(of: PortfolioHealthPanel(store: store), size: CGSize(width: 400, height: 500))
        let watchlist = try OverviewModelWiringTests.texts(of: PriceWatchlist(store: store), size: CGSize(width: 400, height: 500))
        let chart = try OverviewModelWiringTests.texts(of: PortfolioValueChart(store: portfolio), size: CGSize(width: 800, height: 300))

        #expect(Self.values(after: ["Stablecoins & Fiat", majors, "Tokens & Memecoins"], in: cards) == [eur(0), eur(6100), eur(0)], "\(cards)")
        #expect(Self.values(after: ["Lending", "Staked", "Yield", "Other"], in: cards) == [eur(4000), eur(0), eur(0), eur(0)], "\(cards)")
        #expect(Self.values(after: ["Borrowed"], in: cards) == [eur(500)], "\(cards)")
        #expect(tabs.contains("Primary Wallet") && tabs.contains("ETH") && tabs.contains(eur(6100)), "\(tabs)")
        #expect(borrowing.contains("Aave V3") && borrowing.contains("USDC") && borrowing.contains(eur(500)), "\(borrowing)")
        #expect(donut.contains("ETH") && donut.contains("USDC"), "\(donut)")
        #expect(health.contains("Portfolio Health") && health.contains("Assets") && health.contains("ETH"), "\(health)")
        #expect(watchlist.contains(OverviewPriceDisplay.assetLabel("ETH")), "\(watchlist)")
        #expect(watchlist.contains(OverviewPriceDisplay.price(3050 * Self.rate, currencyCode: "EUR")), "\(watchlist)")
        #expect(!chart.contains("No Data") && !chart.contains("—"), "\(chart)")
        #expect(store.portfolio.valueChart?.snapshots.count == 5)
        for panel in [cards, tabs, donut, chart] {
            #expect(!panel.contains("—"), "\(panel)")
        }
    }

    /// With backfill on, the month before the first snapshot has an estimate, drawn dashed with its
    /// caption; with it off, neither the estimate nor the caption.
    @Test(.renderedTextReadable, arguments: [true, false])
    func `the chart captions its estimate only with backfill on`(backfill: Bool) async throws {
        let container = try makeContainer()
        try insertEstimatePrices(in: container)
        let store = Self.overviewStore(
            over: container,
            settings: DashboardSettings(dashboard: .defaults, isHistoricalBackfillEnabled: backfill, watchlistIDs: []))
        try await Self.built(store)

        let texts = try OverviewModelWiringTests.texts(
            of: PortfolioValueChart(store: store.scope(state: \.portfolio, action: \.portfolio)),
            size: CGSize(width: 800, height: 300))

        #expect(store.portfolio.valueChart?.estimated.isEmpty == !backfill, "the store estimates only with backfill on")
        #expect(texts.contains(Self.estimateCaption) == backfill, "\(texts)")
        #expect(!texts.contains("No Data"), "\(texts)")
    }

    // MARK: - After an empty build

    /// An empty store builds an empty portfolio: every panel shows today's empty text and no dash.
    @Test(.renderedTextReadable) func `an empty portfolio shows each panel's empty text after a build`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let store = Self.overviewStore(over: container)
        try await Self.built(store)
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)

        let cards = try OverviewModelWiringTests.texts(of: OverviewSummaryCards(store: portfolio), size: CGSize(width: 1200, height: 300))
        let tabs = try OverviewModelWiringTests.texts(of: OverviewPositionTabs(store: portfolio), size: CGSize(width: 1000, height: 500))
        let donut = try OverviewModelWiringTests.texts(of: TopAssetsDonut(store: store), size: CGSize(width: 600, height: 400))
        let health = try OverviewModelWiringTests.texts(of: PortfolioHealthPanel(store: store), size: CGSize(width: 400, height: 500))
        let watchlist = try OverviewModelWiringTests.texts(of: PriceWatchlist(store: store), size: CGSize(width: 400, height: 500))
        let chart = try OverviewModelWiringTests.texts(of: PortfolioValueChart(store: portfolio), size: CGSize(width: 800, height: 300))

        #expect(cards.count { $0 == OverviewPriceDisplay.currency(0, currencyCode: "EUR") } == 8, "\(cards)")
        #expect(tabs.contains(OverviewPositionTab.keyChanges.emptyMessage), "\(tabs)")
        #expect(donut.contains("No data"), "\(donut)")
        #expect(health.contains("Portfolio Health") && health.contains("Assets"), "\(health)")
        #expect(watchlist.contains("No priced assets"), "\(watchlist)")
        #expect(chart.contains("No Data"), "\(chart)")
        for panel in [cards, tabs, donut, watchlist, chart] {
            #expect(!panel.contains("—"), "\(panel)")
        }
    }

    // MARK: - Before the first build

    /// Nothing is valued yet, so a panel claiming "no data" would claim an empty portfolio.
    @Test(.renderedTextReadable) func `the overview panels show a dash and no empty text before the first build`() throws {
        let store = try Self.overviewStore(over: makeContainer())
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)

        let cards = try OverviewModelWiringTests.texts(of: OverviewSummaryCards(store: portfolio), size: CGSize(width: 1200, height: 300))
        let tabs = try OverviewModelWiringTests.texts(of: OverviewPositionTabs(store: portfolio), size: CGSize(width: 1000, height: 500))
        let donut = try OverviewModelWiringTests.texts(of: TopAssetsDonut(store: store), size: CGSize(width: 600, height: 400))
        let health = try OverviewModelWiringTests.texts(of: PortfolioHealthPanel(store: store), size: CGSize(width: 400, height: 500))
        let watchlist = try OverviewModelWiringTests.texts(of: PriceWatchlist(store: store), size: CGSize(width: 400, height: 500))
        let chart = try OverviewModelWiringTests.texts(of: PortfolioValueChart(store: portfolio), size: CGSize(width: 800, height: 300))

        #expect(cards.count { $0 == "—" } == 8, "every row of the three cards: \(cards)")
        for panel in [tabs, donut, health, watchlist, chart] {
            #expect(panel.contains("—"), "\(panel)")
        }
        let empties = OverviewPositionTab.allCases.map(\.emptyMessage) + ["No data", "No priced assets", "No Data"]
        for panel in [cards, tabs, donut, health, watchlist, chart] {
            #expect(empties.allSatisfy { !panel.contains($0) }, "\(panel)")
        }
        #expect(store.portfolio.overview == OverviewPanels())
        #expect(store.portfolio.valueChart == nil)
    }

    // MARK: - Tooltips

    /// The panels that carry a failed first build's error on their dash.
    enum DashedPanel: CaseIterable {
        case cards, tabs, donut, health, watchlist
    }

    /// The first tooltip of `panel` rendered over `store`, nil if it has none.
    private func tooltip(of panel: DashedPanel, over store: StoreOf<AppFeature>) -> String? {
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)
        let rendered = switch panel {
        case .cards: render(OverviewSummaryCards(store: portfolio), size: CGSize(width: 1200, height: 300))
        case .tabs: render(OverviewPositionTabs(store: portfolio), size: CGSize(width: 1000, height: 500))
        case .donut: render(TopAssetsDonut(store: store), size: CGSize(width: 600, height: 400))
        case .health: render(PortfolioHealthPanel(store: store), size: CGSize(width: 400, height: 500))
        case .watchlist: render(PriceWatchlist(store: store), size: CGSize(width: 400, height: 500))
        }
        return Self.helpText(rendered)
    }

    /// A failed first build says so on each dashed panel, as it does on the dashed headline. The launch
    /// transient's dashes and a shown panel carry no tooltip, even with an older failure recorded.
    @Test(.renderedTextReadable, arguments: DashedPanel.allCases)
    func `a dashed panel carries a failed first build's error`(_ panel: DashedPanel) {
        let failed = tooltip(of: panel, over: OverviewModelWiringTests.appStore(buildError: "store unavailable"))
        let loading = tooltip(of: panel, over: OverviewModelWiringTests.appStore())
        let shown = tooltip(of: panel, over: OverviewModelWiringTests.appStore(Self.fixtureRevaluation, buildError: "store unavailable"))

        #expect(failed == OverviewPriceDisplay.unavailableHelp(buildError: "store unavailable"))
        #expect(failed == "Portfolio unavailable: store unavailable")
        #expect(loading == nil)
        #expect(shown == nil)
    }

    /// The chart is built on its own and a failure of its build is logged, so its dash has no error
    /// to show: it carries no tooltip, nor after a failed holdings build.
    @Test(.renderedTextReadable, arguments: [nil, "store unavailable"])
    func `the chart carries no error tooltip even after a failed holdings build`(_ buildError: String?) {
        let store = OverviewModelWiringTests.appStore(buildError: buildError)
        let portfolio = store.scope(state: \.portfolio, action: \.portfolio)

        let help = Self.helpText(render(PortfolioValueChart(store: portfolio), size: CGSize(width: 800, height: 300)))

        #expect(help == nil)
        #expect(store.portfolio.valueChart == nil, "the chart is dashed")
    }

    // MARK: - Fixtures

    /// `sliceStore` over `container`'s projectors, dated by the seeded data.
    static func overviewStore(over container: ModelContainer, settings: DashboardSettings = .defaults) -> StoreOf<AppFeature> {
        sliceStore(
            projector: .live(modelContainer: container),
            chartProjector: .live(modelContainer: container),
            now: seededNow,
            settings: settings)
    }

    /// Starts the dashboard task and waits for its first builds.
    static func built(_ store: StoreOf<AppFeature>) async throws {
        store.send(.portfolio(.task))
        try await awaitBuilds(of: store)
    }

    /// Waits, with the main actor free for the builds' results to land, until the dashboard task's
    /// first holdings build, valuation and chart conversion have. Given a `view`, lays it out each
    /// turn and once more at the end, so its panels render what landed: an offscreen hosting view
    /// re-evaluates its body only when laid out.
    static func awaitBuilds(of store: StoreOf<AppFeature>, relayouting view: NSView? = nil) async throws {
        let deadline = Date().addingTimeInterval(10)
        while store.portfolio.valued == nil || store.portfolio.valueChart == nil, Date() < deadline {
            relayout(view)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.portfolio.valued != nil && store.portfolio.valueChart != nil, "the dashboard task's first builds never landed")
        relayout(view)
    }

    private static func relayout(_ view: NSView?) {
        guard let view else { return }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    /// The text that follows each label in `texts`, the order a card exposes its row label and value.
    private static func values(after labels: [String], in texts: [String]) -> [String?] {
        labels.map { label in
            texts.firstIndex(of: label).flatMap { texts.indices.contains($0 + 1) ? texts[$0 + 1] : nil }
        }
    }

    /// The valuation fixture's panels, as a build leaves them.
    private static var fixtureRevaluation: PortfolioRevaluation {
        PortfolioValuator.compute(PortfolioValuationRequest(
            projection: .fixture(historical: PortfolioValuationFixture.historical),
            prices: PortfolioPriceInputs(
                livePricesUSD: PortfolioValuationFixture.livePricesUSD,
                liveChanges24h: PortfolioValuationFixture.liveChanges24h,
                usdToDisplayRate: 1,
                currency: .usd),
            settings: .defaults))
    }

    /// USD closes for ETH and USDC on each of the 25 days before the first snapshot, so a backfilled
    /// chart has an estimate to draw.
    private func insertEstimatePrices(in container: ModelContainer) throws {
        let firstSnapshotDay = Self.seededNow.addingTimeInterval(-4 * 86400)
        for offset in 1 ... 25 {
            let day = HistoricalPriceCalendar.utcStartOfDay(for: firstSnapshotDay.addingTimeInterval(Double(-offset) * 86400))
            container.mainContext.insert(HistoricalPricePoint(coinGeckoId: "ethereum", day: day, currency: .usd, price: 3000))
            container.mainContext.insert(HistoricalPricePoint(coinGeckoId: "usd-coin", day: day, currency: .usd, price: 1))
        }
        try container.mainContext.save()
    }
}
