import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The seam inputs the Overview views build from their queries: the shared headline input (top bar
/// and Sidebar header), the cards input and the Health input, and the `ValuationSources`
/// every Overview view reads them through. One store, in memory:
///
/// | Token | Account | Amount | `usdValue` | USD value |
/// |---|---|---|---|---|
/// | ETH | active | 2 | 5800 | 6000 (live 3000, 24h +25% from the live changes only) |
/// | DEGEN | active | 10,000 | 95 | 100 (Degen-chain token mapped to `degen-base`, live 0.01; sync 95) |
/// | BTC | inactive | 1 | 60000 | not valued |
///
/// The display book `appState.prices` holds ten times the USD book, so a view that read it would
/// show other numbers. The rate is 0.9.
@MainActor
struct OverviewModelWiringTests {
    private typealias Fixture = PortfolioValuationFixture

    private static let degenContract = "0xde9e000000000000000000000000000000000de9"
    static let rate = Fixture.decimal("0.9")

    @Test func `the active portfolio headline values the usd book with mappings and live changes`() throws {
        let store = try Store()

        let headline = OverviewFeature.headline(.activePortfolio(
            positions: store.positions,
            overrides: [],
            mappings: store.mappings,
            settings: .defaults,
            appState: store.appState,
            historical: .empty,
            includingLiveChanges: true))

        #expect(headline.total == 6100 * Self.rate)
        #expect(headline.change24h == 1200 * Self.rate)
        #expect(headline.changePercentage == Decimal(1200) / Decimal(4900))
    }

    @Test func `cards value a mapped token through its identity mapping`() throws {
        let store = try Store()

        let cards = OverviewSummaryCardsFeature.cards(
            .activePortfolio(
                positions: store.positions,
                overrides: [],
                mappings: store.mappings,
                settings: .defaults,
                categoryResolver: .defaults,
                appState: store.appState,
                historical: .empty,
                includingLiveChanges: false),
            categories: PortfolioCategoryDefaults.categorySnapshots)
        let idle = try #require(cards.first { $0.title == "Idle" })

        #expect(idle.rows.map(\.value) == [0, 6000 * Self.rate, 100 * Self.rate])
    }

    @Test func `health weights a mapped token through its identity mapping`() throws {
        let store = try Store()

        let health = PortfolioHealthFeature.health(.activeAccounts(
            store.tokens,
            overrides: [],
            mappings: store.mappings,
            settings: .defaults,
            usdToDisplayRate: Self.rate,
            prices: ValuationPriceInputs(livePricesUSD: store.appState.livePricesUSD)))

        #expect(health.weights.map(\.symbol) == ["ETH", "DEGEN"])
        #expect(health.weights.map(\.usdValue) == [6000 * Self.rate, 100 * Self.rate])
        #expect(health.metrics.assetCount == 2)
    }

    @Test func `an ignore override from the store excludes the token`() throws {
        let store = try Store()
        let degen = try #require(store.tokens.first { $0.asset?.symbol == "DEGEN" }?.asset)

        let headline = OverviewFeature.headline(.activePortfolio(
            positions: store.positions,
            overrides: [TokenPricingOverride(assetId: degen.id, isIgnored: true)],
            mappings: store.mappings,
            settings: .defaults,
            appState: store.appState,
            historical: .empty,
            includingLiveChanges: true))

        #expect(headline.total == 6000 * Self.rate)
    }

    @Test(arguments: [false, true])
    func `the overview price inputs read the usd book, not the display book`(includingLiveChanges: Bool) throws {
        let store = try Store()
        let historical = HistoricalMarketPrices(closesUSD: [:], changes24h: ["bitcoin": Fixture.decimal("0.02")])

        let prices = ValuationPriceInputs.live(store.appState, historical: historical, includingLiveChanges: includingLiveChanges)

        #expect(prices.livePricesUSD == store.appState.livePricesUSD)
        #expect(prices.liveChanges24h == (includingLiveChanges ? store.appState.priceChanges24h : [:]))
        #expect(prices.historical == historical)
    }

    // MARK: - Probe

    private static var retainedWindows: [NSWindow] = []

    /// Renders a view that reads `ValuationSources` from the store, as the Overview views do,
    /// and returns what `build` made on its last body pass. The view's `@AppStorage` reads a fresh,
    /// empty defaults suite, so the dashboard settings are the defaults whatever the test host stores.
    static func probe<Value>(
        _ store: Store,
        _ build: @escaping @MainActor (ValuationSources, [Position], [PositionToken], [Asset]) -> Value) -> Value? {
        let capture = Capture<Value>()
        let rendered = render(SourcesProbe { sources, positions, tokens, assets in
            capture.value = build(sources, positions, tokens, assets)
        }, over: store)
        return rendered == nil ? nil : capture.value
    }

    /// Hosts `view` in a window over the store's container and `AppState`, with `@AppStorage` on a
    /// fresh, empty defaults suite.
    @discardableResult
    static func render(_ view: some View, over store: Store, size: CGSize = CGSize(width: 200, height: 200)) -> NSHostingView<AnyView>? {
        let suiteName = "OverviewModelWiringTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hostingView = NSHostingView(rootView: AnyView(view
                .modelContainer(store.container)
                .environment(store.appState)
                .defaultAppStorage(defaults)))
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        retainedWindows.append(window)
        return hostingView
    }

    /// The resolver an `OverviewCategorySource` builds from the store, on a rendered view's last
    /// body pass.
    static func categoryResolver(_ store: Store) -> PortfolioCategoryResolver? {
        let capture = Capture<PortfolioCategoryResolver>()
        let rendered = render(CategorySourceProbe { capture.value = $0 }, over: store)
        return rendered == nil ? nil : capture.value
    }

    @MainActor
    private final class Capture<Value> {
        var value: Value?
    }

    private struct SourcesProbe: View {
        var sources = ValuationSources()
        @Query private var positions: [Position]
        @Query private var tokens: [PositionToken]
        @Query private var assets: [Asset]
        let report: @MainActor (ValuationSources, [Position], [PositionToken], [Asset]) -> Void

        var body: some View {
            report(sources, positions, tokens, assets)
            return Color.clear
        }
    }

    private struct CategorySourceProbe: View {
        var categories = OverviewCategorySource()
        let report: @MainActor (PortfolioCategoryResolver) -> Void

        var body: some View {
            report(categories.resolver)
            return Color.clear
        }
    }

    @MainActor
    struct Store {
        let container: ModelContainer
        let positions: [Position]
        let tokens: [PositionToken]
        let mappings: [TokenIdentityMapping]
        let appState: AppState

        /// `ignoring` adds an ignore override row for each listed symbol.
        init(ignoring ignoredSymbols: Set<String> = []) throws {
            self.container = try ModelContainer(
                for: Account.self, Position.self, PositionToken.self, Asset.self, TokenIdentityMapping.self,
                TokenPricingOverride.self, PortfolioCategory.self, CategorySymbolRule.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = container.mainContext
            let syncedAt = Fixture.noon(0)

            let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
            let degen = Asset(
                symbol: "DEGEN",
                name: "Degen",
                upsertChain: .degen,
                upsertContract: OverviewModelWiringTests.degenContract,
                category: .meme)
            let btc = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major)

            let active = Account(name: "Active Wallet", kind: .wallet, dataSource: .zerion)
            let inactive = Account(name: "Old Wallet", kind: .wallet, dataSource: .zerion, isActive: false)
            let wallet = Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 5895,
                tokens: [
                    PositionToken(role: .balance, amount: 2, usdValue: 5800, asset: eth),
                    PositionToken(role: .balance, amount: 10000, usdValue: 95, asset: degen)
                ],
                account: active,
                syncedAt: syncedAt)
            let oldWallet = Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 60000,
                tokens: [PositionToken(role: .balance, amount: 1, usdValue: 60000, asset: btc)],
                account: inactive,
                syncedAt: syncedAt)
            active.positions = [wallet]
            inactive.positions = [oldWallet]

            for model in [eth, degen, btc] {
                context.insert(model)
            }
            context.insert(active)
            context.insert(inactive)
            context.insert(TokenIdentityMapping(
                chain: .degen,
                contractAddress: OverviewModelWiringTests.degenContract,
                coinGeckoId: "degen-base"))
            for asset in [eth, degen, btc] where ignoredSymbols.contains(asset.symbol) {
                context.insert(TokenPricingOverride(assetId: asset.id, isIgnored: true))
            }
            try context.save()

            self.positions = try context.fetch(FetchDescriptor<Position>())
            self.tokens = try context.fetch(FetchDescriptor<PositionToken>())
            self.mappings = try context.fetch(FetchDescriptor<TokenIdentityMapping>())

            let livePricesUSD: [String: Decimal] = ["ethereum": 3000, "degen-base": Fixture.decimal("0.01"), "bitcoin": 60000]
            self.appState = AppState()
            appState.livePricesUSD = livePricesUSD
            appState.prices = livePricesUSD.mapValues { $0 * 10 }
            appState.priceChanges24h = ["ethereum": Fixture.decimal("0.25")]
            appState.currentUSDToDisplayRate = OverviewModelWiringTests.rate
        }

        /// Adds rows after setup; a probe's queries read them on its first body pass.
        func insert(_ models: [any PersistentModel]) throws {
            for model in models {
                container.mainContext.insert(model)
            }
            try container.mainContext.save()
        }

        /// The seeded categories, with the BTC and ETH categories renamed "Majors" and "L1s", and a
        /// user rule that files DEGEN under Stablecoins.
        func seedCategories() throws {
            let context = container.mainContext
            try PortfolioCategorySeeder.seedIfNeeded(in: context)
            let categories = try context.fetch(FetchDescriptor<PortfolioCategory>())
            let names = [PortfolioCategoryDefaults.btcCategoryID: "Majors", PortfolioCategoryDefaults.ethCategoryID: "L1s"]
            for category in categories {
                category.name = names[category.id] ?? category.name
            }
            let stablecoins = categories.first { $0.id == PortfolioCategoryDefaults.stablecoinsCategoryID }
            try insert([CategorySymbolRule(normalizedSymbol: "DEGEN", category: stablecoins)])
        }

        /// A $0.50 holding in the active wallet, below the default $1 dust threshold.
        func addDust() throws {
            let wallet = try #require(positions.first { $0.account?.isActive == true })
            let dust = Asset(symbol: "DUST", name: "Dust", category: .meme)
            let usdValue = PortfolioValuationFixture.decimal("0.5")
            try insert([dust, PositionToken(role: .balance, amount: 1, usdValue: usdValue, asset: dust, position: wallet)])
        }
    }
}
