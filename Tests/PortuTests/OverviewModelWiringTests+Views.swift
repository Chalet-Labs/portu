import AppKit
import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The Overview views themselves, rendered over the in-memory store and read back through the
/// accessibility tree, so a view that built its numbers some other way than through its
/// `ValuationSources` method would show other text.
extension OverviewModelWiringTests {
    /// The mapping row values DEGEN at 100, ETH's +25% is only in `appState.priceChanges24h`, and
    /// the ignore row (second case) drops DEGEN.
    @Test(.renderedTextReadable, arguments: [false, true])
    func `the top bar and sidebar header show the sources headline`(ignoringDegen: Bool) throws {
        let store = try Store(ignoring: ignoringDegen ? ["DEGEN"] : [])
        let expected = try #require(Self.probe(store) { sources, positions, _, _ in sources.headline(positions) })
        let currencyCode = store.appState.selectedCurrency.displayCode
        let shown = [
            OverviewPriceDisplay.currency(expected.total, currencyCode: currencyCode),
            OverviewPriceDisplay.currency(expected.change24h, currencyCode: currencyCode),
            OverviewPriceDisplay.changePercentage(expected.changePercentage)
        ]

        #expect(expected.total == (ignoringDegen ? 6000 : 6100) * Self.rate)
        #expect(expected.change24h == 1200 * Self.rate)
        for view in [AnyView(OverviewTopBar()), AnyView(SidebarPortfolioHeader())] {
            let texts = try Self.texts(of: view, over: store)
            #expect(shown.allSatisfy(texts.contains), "\(texts)")
        }
    }

    /// A 3 ETH borrow outweighs the holdings, so the prior total (−2900 + 600) is not positive: both
    /// headers show "—", and the top bar drops the arrow it draws next to a percentage.
    @Test(.renderedTextReadable) func `the top bar and sidebar header show a dash and no arrow without a positive prior`() throws {
        let store = try Store()
        let wallet = try #require(store.positions.first { $0.account?.isActive == true })
        let eth = try #require(wallet.tokens.first { $0.asset?.symbol == "ETH" }?.asset)
        try store.insert([PositionToken(role: .borrow, amount: 3, usdValue: 8700, asset: eth, position: wallet)])
        let headline = try #require(Self.probe(store) { sources, positions, _, _ in sources.headline(positions) })

        #expect(headline.changePercentage == nil)
        for view in [AnyView(OverviewTopBar()), AnyView(SidebarPortfolioHeader())] {
            let texts = try Self.texts(of: view, over: store)
            #expect(texts.contains("—"), "\(texts)")
        }
        let arrows = try Self.images(of: OverviewTopBar(), over: Store())
        #expect(!arrows.isEmpty, "the positive-prior top bar draws its arrow")
        #expect(try Self.images(of: OverviewTopBar(), over: store).isEmpty)
    }

    /// The cards view builds its resolver from the store's categories and rules: renamed major
    /// categories and a DEGEN → Stablecoins rule.
    @Test(.renderedTextReadable) func `the cards view uses the store's categories and rules`() throws {
        let store = try Store()
        try store.seedCategories()
        let currencyCode = store.appState.selectedCurrency.displayCode

        let texts = try Self.texts(of: OverviewSummaryCards(), over: store, size: CGSize(width: 1200, height: 300))
        // Each row's label is followed by its value (the tree runs across the cards row by row).
        let idle = ["Stablecoins & Fiat", "Majors / L1s / SOL", "Tokens & Memecoins"].map { label in
            texts.firstIndex(of: label).flatMap { texts.indices.contains($0 + 1) ? texts[$0 + 1] : nil }
        }

        #expect(idle == [100, 6000, 0].map { OverviewPriceDisplay.currency($0 * Self.rate, currencyCode: currencyCode) }, "\(texts)")
    }

    /// The Idle Stables tab shows DEGEN only under the store's DEGEN → Stablecoins rule.
    @Test(.renderedTextReadable) func `the position tabs view uses the store's categories and rules`() throws {
        let store = try Store()
        try store.seedCategories()

        let texts = try Self.texts(of: OverviewPositionTabs(), over: store, size: CGSize(width: 800, height: 400), pressing: "Idle Stables")

        #expect(texts.contains("DEGEN"), "\(texts)")
        #expect(!texts.contains(OverviewPositionTab.idleStables.emptyMessage), "\(texts)")
    }

    /// Category mode files DEGEN under the store's Stablecoins category.
    @Test(.renderedTextReadable) func `the donut view uses the store's categories and rules`() throws {
        let store = try Store()
        try store.seedCategories()

        let texts = try Self.texts(
            of: TopAssetsDonut(store: Self.appStore()),
            over: store,
            size: CGSize(width: 600, height: 400),
            pressing: TopAssetMode.category.title)

        #expect(texts.contains("Stablecoins"), "\(texts)")
        #expect(texts.contains("L1s"), "\(texts)")
    }

    /// DEGEN (100 of 6100) is the only stablecoin, under the store's rule.
    @Test(.renderedTextReadable) func `the health view uses the store's categories and rules`() throws {
        let store = try Store()
        try store.seedCategories()

        let texts = try Self.texts(of: PortfolioHealthPanel(store: Self.appStore()), over: store, size: CGSize(width: 400, height: 400))
        // The metric values come first, then their labels: Assets, Chains, Stables, HHI.
        let stables = texts.firstIndex(of: "Assets").flatMap { $0 >= 4 ? texts[$0 - 2] : nil }

        #expect(stables == (Decimal(100) / Decimal(6100)).formatted(.percent.precision(.fractionLength(0))), "\(texts)")
        #expect(stables != Decimal.zero.formatted(.percent.precision(.fractionLength(0))))
    }

    /// The hidden line pairs its amount, converted at `AppState`'s rate, with `AppState`'s currency
    /// code, so it never shows the new code with the old rate while the store's currency switches.
    @Test(.renderedTextReadable) func `the health hidden line uses the app state currency code`() throws {
        let store = try Store()
        try store.addDust()
        store.appState.selectedCurrency = .chf
        let appStore = Self.appStore()

        let texts = try Self.texts(of: PortfolioHealthPanel(store: appStore), over: store, size: CGSize(width: 400, height: 400))
        let line = { (code: String) in
            OverviewPriceDisplay.hiddenBalancesLine(
                value: PortfolioValuationFixture.decimal("0.5") * Self.rate,
                rowCount: 1,
                isAllDust: true,
                currencyCode: code)
        }

        #expect(appStore.selectedCurrency == .usd)
        #expect(texts.contains(line(FiatCurrency.chf.displayCode)), "\(texts)")
        #expect(!texts.contains(line(FiatCurrency.usd.displayCode)), "\(texts)")
    }

    /// The text every element in the rendered view exposes, in tree order. `pressing` names a
    /// button to press first (a tab or a mode the view starts without).
    static func texts(
        of view: some View,
        over store: Store,
        size: CGSize = CGSize(width: 400, height: 200),
        pressing button: String? = nil) throws -> [String] {
        let hostingView = try #require(render(view, over: store, size: size))
        if let button {
            try #require(press(button, in: hostingView), "no button \(button) in \(accessibilityTexts(hostingView))")
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }
        return accessibilityTexts(hostingView)
    }

    /// An `AppFeature` store for the views that take one; nothing is sent while they render.
    static func appStore() -> StoreOf<AppFeature> {
        StoreOf<AppFeature>(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { _ in SyncResult(failedAccounts: []) }
            $0.priceService.fetchPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.invalidateCache = {}
            $0.continuousClock = TestClock()
        }
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
    static func images(of view: some View, over store: Store) throws -> [String] {
        let hostingView = try #require(render(view, over: store, size: CGSize(width: 400, height: 200)))
        return accessibilityImages(hostingView)
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

    private static func accessibilityTexts(_ element: Any) -> [String] {
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

    /// Whether this host builds SwiftUI's accessibility tree, which `texts(of:over:)` reads.
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
    /// exists; `OverviewModelWiringTests`' probe tests pin the same sources on every host.
    static var renderedTextReadable: Self {
        .enabled("SwiftUI builds no accessibility tree on this host") {
            await MainActor.run { OverviewModelWiringTests.renderedTextIsReadable() }
        }
    }
}
