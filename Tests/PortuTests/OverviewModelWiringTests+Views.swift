import AppKit
import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The Overview views themselves, rendered from a store holding what the read model values from the
/// in-memory store and read back through the accessibility tree, so a view that built its numbers some
/// other way than from the reducer's state would show other text.
extension OverviewModelWiringTests {
    /// The mapping row values DEGEN at 100, ETH's +25% is only in the live fractions, and the ignore
    /// row (second case) drops DEGEN.
    @Test(.renderedTextReadable, arguments: [false, true])
    func `the top bar and sidebar header show the read model's headline`(ignoringDegen: Bool) async throws {
        let store = try Store(ignoring: ignoringDegen ? ["DEGEN"] : [])
        let revaluation = try await Self.readModel(store)
        let expected = revaluation.valued.headline
        let shown = [
            OverviewPriceDisplay.currency(expected.total, currencyCode: revaluation.valued.currencyCode),
            OverviewPriceDisplay.currency(expected.change24h, currencyCode: revaluation.valued.currencyCode),
            OverviewPriceDisplay.changePercentage(expected.changePercentage)
        ]

        #expect(expected.total == (ignoringDegen ? 6000 : 6100) * Self.rate)
        #expect(expected.change24h == 1200 * Self.rate)
        for view in Self.sliceViews(revaluation) {
            let texts = try Self.texts(of: view)
            #expect(shown.allSatisfy(texts.contains), "\(texts)")
        }
    }

    /// A 3 ETH borrow outweighs the holdings, so the prior total (−2900 + 600) is not positive: both
    /// headers show "—", and the top bar drops the arrow it draws next to a percentage.
    @Test(.renderedTextReadable) func `the top bar and sidebar header show a dash and no arrow without a positive prior`() async throws {
        let store = try Store()
        let wallet = try #require(store.positions.first { $0.account?.isActive == true })
        let eth = try #require(wallet.tokens.first { $0.asset?.symbol == "ETH" }?.asset)
        try store.insert([PositionToken(role: .borrow, amount: 3, usdValue: 8700, asset: eth, position: wallet)])
        let borrowing = try await Self.readModel(store)
        let positive = try await Self.readModel(Store())

        #expect(borrowing.valued.headline.changePercentage == nil)
        for view in Self.sliceViews(borrowing) {
            let texts = try Self.texts(of: view)
            #expect(texts.contains("—"), "\(texts)")
        }
        #expect(try !Self.images(of: Self.topBar(positive)).isEmpty, "the positive-prior top bar draws its arrow")
        #expect(try Self.images(of: Self.topBar(borrowing)).isEmpty)
    }

    /// A portfolio store holding `revaluation`, as the dashboard holds it after a build.
    static func portfolioStore(_ revaluation: PortfolioRevaluation?) -> StoreOf<PortfolioFeature> {
        var state = PortfolioFeature.State()
        state.projection = .empty
        state.store(revaluation)
        return StoreOf<PortfolioFeature>(initialState: state) { PortfolioFeature() }
    }

    private static func topBar(_ revaluation: PortfolioRevaluation) -> OverviewTopBar {
        OverviewTopBar(store: portfolioStore(revaluation))
    }

    private static func sliceViews(_ revaluation: PortfolioRevaluation) -> [AnyView] {
        [AnyView(topBar(revaluation)), AnyView(SidebarPortfolioHeader(store: portfolioStore(revaluation)))]
    }

    /// The cards show the store's renamed major categories, and its DEGEN → Stablecoins rule.
    @Test(.renderedTextReadable) func `the cards view shows the store's categories and rules`() async throws {
        let store = try Store()
        try store.seedCategories()
        let revaluation = try await Self.readModel(store)
        let currencyCode = revaluation.overview.currencyCode

        let texts = try Self.texts(of: OverviewSummaryCards(store: Self.portfolioStore(revaluation)), size: CGSize(width: 1200, height: 300))
        // Each row's label is followed by its value (the tree runs across the cards row by row).
        let idle = ["Stablecoins & Fiat", "Majors / L1s / SOL", "Tokens & Memecoins"].map { label in
            texts.firstIndex(of: label).flatMap { texts.indices.contains($0 + 1) ? texts[$0 + 1] : nil }
        }

        #expect(idle == [100, 6000, 0].map { OverviewPriceDisplay.currency($0 * Self.rate, currencyCode: currencyCode) }, "\(texts)")
    }

    /// The Idle Stables tab shows DEGEN only under the store's DEGEN → Stablecoins rule.
    @Test(.renderedTextReadable) func `the position tabs view shows the store's categories and rules`() async throws {
        let store = try Store()
        try store.seedCategories()
        let revaluation = try await Self.readModel(store)

        let texts = try Self.texts(
            of: OverviewPositionTabs(store: Self.portfolioStore(revaluation)),
            size: CGSize(width: 800, height: 400),
            pressing: "Idle Stables")

        #expect(texts.contains("DEGEN"), "\(texts)")
        #expect(!texts.contains(OverviewPositionTab.idleStables.emptyMessage), "\(texts)")
    }

    /// Category mode files DEGEN under the store's Stablecoins category.
    @Test(.renderedTextReadable) func `the donut view shows the store's categories and rules`() async throws {
        let store = try Store()
        try store.seedCategories()
        let revaluation = try await Self.readModel(store)

        let texts = try Self.texts(
            of: TopAssetsDonut(store: Self.appStore(revaluation)),
            size: CGSize(width: 600, height: 400),
            pressing: TopAssetMode.category.title)

        #expect(texts.contains("Stablecoins"), "\(texts)")
        #expect(texts.contains("L1s"), "\(texts)")
    }

    /// DEGEN (100 of 6100) is the only stablecoin, under the store's rule.
    @Test(.renderedTextReadable) func `the health view shows the store's categories and rules`() async throws {
        let store = try Store()
        try store.seedCategories()
        let revaluation = try await Self.readModel(store)

        let texts = try Self.texts(of: PortfolioHealthPanel(store: Self.appStore(revaluation)), size: CGSize(width: 400, height: 400))
        // The metric values come first, then their labels: Assets, Chains, Stables, HHI.
        let stables = texts.firstIndex(of: "Assets").flatMap { $0 >= 4 ? texts[$0 - 2] : nil }

        #expect(stables == (Decimal(100) / Decimal(6100)).formatted(.percent.precision(.fractionLength(0))), "\(texts)")
        #expect(stables != Decimal.zero.formatted(.percent.precision(.fractionLength(0))))
    }

    /// The hidden line pairs its amount with the code of the currency the revaluation converted it
    /// in, so it never shows the new code with the old amount while the store's currency switches:
    /// the store has switched to CHF, the panel still holds the USD revaluation, and shows USD.
    @Test(.renderedTextReadable) func `the health hidden line uses the currency code of its revaluation`() async throws {
        let store = try Store()
        try store.addDust()
        let usd = try await Self.readModel(store)
        store.appState.selectedCurrency = .chf
        let chf = try await Self.readModel(store)
        let line = { (code: String) in
            OverviewPriceDisplay.hiddenBalancesLine(
                value: PortfolioValuationFixture.decimal("0.5") * Self.rate,
                rowCount: 1,
                isAllDust: true,
                currencyCode: code)
        }

        let size = CGSize(width: 400, height: 400)
        let converted = try Self.texts(of: PortfolioHealthPanel(store: Self.appStore(chf)), size: size)
        let switching = try Self.texts(of: PortfolioHealthPanel(store: Self.appStore(usd, selectedCurrency: .chf)), size: size)

        #expect(converted.contains(line(FiatCurrency.chf.displayCode)), "\(converted)")
        #expect(switching.contains(line(FiatCurrency.usd.displayCode)), "\(switching)")
        #expect(!switching.contains(line(FiatCurrency.chf.displayCode)), "\(switching)")
    }

    /// The text every element in the rendered view exposes, in tree order. `pressing` names a
    /// button to press first (a tab or a mode the view starts without).
    static func texts(
        of view: some View,
        size: CGSize = CGSize(width: 400, height: 200),
        pressing button: String? = nil) throws -> [String] {
        let hostingView = render(view, size: size)
        if let button {
            try #require(press(button, in: hostingView), "no button \(button) in \(accessibilityTexts(hostingView))")
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }
        return accessibilityTexts(hostingView)
    }

    /// An `AppFeature` store holding `revaluation` and `valueChart` in its portfolio state, and the
    /// failures of the last holdings build and chart build if given, for the views that take one;
    /// nothing is sent while they render.
    static func appStore(
        _ revaluation: PortfolioRevaluation? = nil,
        selectedCurrency: FiatCurrency = .usd,
        buildError: String? = nil,
        valueChart: PortfolioValueChartData? = nil,
        valueChartBuildError: String? = nil) -> StoreOf<AppFeature> {
        var state = AppFeature.State()
        state.selectedCurrency = selectedCurrency
        state.portfolio.projection = .empty
        state.portfolio.buildError = buildError
        state.portfolio.valueChart = valueChart
        state.portfolio.valueChartBuildError = valueChartBuildError
        state.portfolio.store(revaluation)
        return StoreOf<AppFeature>(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { _ in SyncResult(failedAccounts: []) }
            $0.priceService.fetchPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.invalidateCache = {}
            $0.continuousClock = TestClock()
        }
    }

    private static var retainedWindows: [NSWindow] = []

    /// Hosts `view` in a window, laid out and drawn once.
    @discardableResult
    static func render(_ view: some View, size: CGSize = CGSize(width: 200, height: 200)) -> NSHostingView<some View> {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        retainedWindows.append(window)
        return hostingView
    }

    private static func accessibilityString(_ selector: String, of element: Any) -> String? {
        guard let node = element as? NSObject, node.responds(to: NSSelectorFromString(selector)) else { return nil }
        let value = node.perform(NSSelectorFromString(selector))?.takeUnretainedValue()
        if let string = value as? String {
            return string
        }
        return (value as? NSAttributedString)?.string
    }

    private static func press(_ title: String, in element: Any) -> Bool {
        let object = element as AnyObject
        if
            let node = element as? NSObject,
            node.responds(to: NSSelectorFromString("accessibilityPerformPress")),
            accessibilityString("accessibilityRole", of: element) == NSAccessibility.Role.button.rawValue,
            [accessibilityString("accessibilityLabel", of: element), accessibilityString("accessibilityTitle", of: element)].contains(title) {
            node.perform(NSSelectorFromString("accessibilityPerformPress"))
            return true
        }
        for child in object.accessibilityChildren?() ?? [] where press(title, in: child) {
            return true
        }
        return false
    }

    /// The image elements in the rendered view, by their accessibility description or label.
    static func images(of view: some View) throws -> [String] {
        accessibilityImages(render(view, size: CGSize(width: 400, height: 200)))
    }

    private static func accessibilityImages(_ element: Any) -> [String] {
        let object = element as AnyObject
        var images: [String] = []
        if accessibilityString("accessibilityRole", of: element) == NSAccessibility.Role.image.rawValue {
            images.append(accessibilityString("accessibilityLabel", of: element) ?? "")
        }
        for child in object.accessibilityChildren?() ?? [] {
            images += accessibilityImages(child)
        }
        return images
    }

    static func accessibilityTexts(_ element: Any) -> [String] {
        let object = element as AnyObject
        var texts: [String] = []
        if let value = (element as? NSObject)?.value(forKey: "accessibilityValue") as? String, !value.isEmpty {
            texts.append(value)
        }
        for child in object.accessibilityChildren?() ?? [] {
            texts += accessibilityTexts(child)
        }
        return texts
    }

    /// Whether this host builds SwiftUI's accessibility tree, which `texts(of:)` reads.
    static func renderedTextIsReadable() -> Bool {
        let hostingView = NSHostingView(rootView: Text("accessibility probe"))
        hostingView.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        return accessibilityTexts(hostingView).contains("accessibility probe")
    }
}

extension Trait where Self == ConditionTrait {
    /// GitHub's macOS runner builds no SwiftUI accessibility tree, so every rendered element reads
    /// back empty there. Tests that read rendered text skip on such a host and run where the tree
    /// exists; `OverviewModelWiringTests`' read-model tests pin the same outputs on every host.
    static var renderedTextReadable: Self {
        .enabled("SwiftUI builds no accessibility tree on this host") {
            await MainActor.run { OverviewModelWiringTests.renderedTextIsReadable() }
        }
    }
}
