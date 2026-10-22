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

/// `ActivePortfolioProvider` hosted alone and under the production `ContentView`. The dashboard
/// hosts copy `ViewRenderSmokeTests`' (stubbed store, in-memory container, bridged `AppState`), and
/// the counting builder records every projection the provider builds.
@Suite(.serialized)
@MainActor
struct ActivePortfolioProviderTests {
    private typealias Fixture = PortfolioValuationFixture

    private static let maxRetainedWindows = 16
    private static var retainedWindows: [NSWindow] = []
    private static let syncedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A body that reads store state re-runs on every navigation click, and the provider under it
    /// re-fetches and walks the store each time.
    @Test func `the content view body reads no observable store state`() {
        let store = ViewRenderSmokeTests().makeStore(section: .allPositions)
        let view = ContentView(store: store)
        let changed = Mutex(false)

        withObservationTracking {
            _ = view.body
        } onChange: {
            changed.withLock { $0 = true }
        }
        store.send(.sectionSelected(.overview))

        #expect(store.selectedSection == .overview)
        #expect(changed.withLock { $0 } == false, "ContentView.body read store state")
    }

    /// All Positions shows the projection the provider publishes. The headline above it comes from
    /// the portfolio read model since #123 (`ViewRenderSmokeTests+PortfolioSlice`).
    @Test(.renderedTextReadable) func `the All Positions page shows the published projection`() throws {
        let suiteName = "ActivePortfolioProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let smoke = ViewRenderSmokeTests()
        let store = smoke.makeStore(section: .allPositions)
        let appState = AppState()
        appState.bridge(from: store)
        appState.livePricesUSD = Fixture.livePricesUSD
        let portfolio = ActivePortfolioProjection(inputs: Fixture.inputs, cards: AllPositionsSeamFixture.cards)

        let hostingView = try smoke.render(
            ContentView(store: store)
                .modelContainer(ModelContainerFactory().makeInMemory())
                .environment(appState)
                .environment(\.activePortfolioBuilder, ActivePortfolioBuilder { _ in portfolio })
                .defaultAppStorage(defaults)
                .frame(width: 1400, height: 1600),
            size: CGSize(width: 1400, height: 1600))

        // What `ValuationSources` reads: no overrides or mappings in the empty store, the settings
        // of a fresh suite, the app's books and rate, no historical rows.
        let settings = TokenDashboardSettings(
            minimumDashboardValue: Decimal(NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue),
            hideUnpriced: true,
            hideDust: true)
        let context = { (includingLiveChanges: Bool) in
            ValuationContext(
                inputs: portfolio.inputs,
                overrides: [],
                mappings: [],
                settings: settings,
                usdToDisplayRate: appState.currentUSDToDisplayRate,
                prices: .live(appState, historical: .empty, includingLiveChanges: includingLiveChanges))
        }
        let section = try #require(AllPositionsFeature.page(context(false), cards: portfolio.cards, filter: .all).sections.first)
        let expected = [AllPositionsFormat.currency(section.total, code: appState.currencyCode)]
        #expect(section.total != 0)

        var texts = ViewRenderSmokeTests.accessibilityLabels(hostingView)
        let deadline = Date().addingTimeInterval(2)
        while !expected.allSatisfy(texts.contains), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            texts = ViewRenderSmokeTests.accessibilityLabels(hostingView)
        }
        #expect(expected.allSatisfy(texts.contains), "expected \(expected) in \(texts)")
    }

    @Test func `the provider publishes the store's active projection and follows saves`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        let active = Account(name: "Main Wallet", kind: .wallet, dataSource: .zerion)
        let archived = Account(name: "Archived Wallet", kind: .wallet, dataSource: .zerion, isActive: false)
        context.insert(eth)
        context.insert(active)
        context.insert(archived)
        context.insert(Self.position(.idle, [PositionToken(role: .balance, amount: 2, usdValue: 6000, asset: eth)], in: active))
        context.insert(Position(positionType: .lending, protocolId: "aave-v3", protocolName: "Aave V3", account: active, syncedAt: Self.syncedAt))
        context.insert(Self.position(.idle, [PositionToken(role: .balance, amount: 1, usdValue: 3000, asset: eth)], in: archived))
        try context.save()
        let expected = try ActivePortfolioProjection(context.fetch(FetchDescriptor<Position>()))
        #expect(expected.cards.count == 2)
        #expect(expected.inputs.count == 1)

        let counter = BuildCounter()
        let recorder = PortfolioRecorder()
        let hostingView = Self.host(ActivePortfolioProvider { PortfolioSink(recorder: recorder) }
            .modelContainer(container)
            .environment(\.activePortfolioBuilder, counter.builder))

        #expect(waitUntil { Self.sorted(recorder.portfolio) == Self.sorted(expected) }, "\(recorder.portfolio)")
        print("C-P count: T4 mount builds=\(counter.summary)")
        counter.reset()

        let holding = try #require(context.fetch(FetchDescriptor<Position>()).first { $0.account?.isActive == true && !$0.tokens.isEmpty })
        context.delete(holding)
        let token = PositionToken(role: .balance, amount: 3, usdValue: 9000, asset: eth)
        context.insert(Self.position(.idle, [token], in: active))
        try context.save()
        let tokenID = token.id
        #expect(waitUntil { recorder.portfolio.inputs.map(\.tokenId) == [tokenID] }, "\(recorder.portfolio)")
        #expect(recorder.portfolio.cards.count == 2)
        spin(0.5)
        print("C-P count: T4 save builds=\(counter.summary)")
        counter.reset()

        for position in try context.fetch(FetchDescriptor<Position>()) {
            context.delete(position)
        }
        try context.save()
        #expect(waitUntil { recorder.portfolio == ActivePortfolioProjection(inputs: [], cards: []) }, "\(recorder.portfolio)")
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        print("C-P count: T4 delete-all builds=\(counter.summary)")
    }

    @Test func `price ticks and sync status changes build no projection, a save builds one`() throws {
        let suiteName = "ActivePortfolioProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let counter = BuildCounter()
        let dashboard = try Dashboard(section: .allPositions, counter: counter, defaults: defaults)
        let context = dashboard.container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let eth = try #require(assets.first { $0.symbol == "ETH" })
        let usdc = try #require(assets.first { $0.symbol == "USDC" })

        let built = waitUntil { counter.builds >= 1 }
        #expect(built, "the provider never built a projection")
        guard built else { return }
        spin(0.5)
        print("C-P count: T6 mount builds=\(counter.summary)")
        counter.reset()

        dashboard.appState.livePricesUSD["ethereum"] = 3100
        dashboard.appState.syncStatus = .syncing
        spin(0.5)
        print("C-P count: T6 tick and sync status builds=\(counter.summary)")
        #expect(counter.builds == 0, "a price tick or a sync status change rebuilt the projection")
        counter.reset()

        // What a sync does: delete the account's positions, reinsert them on the same assets, save.
        for position in try context.fetch(FetchDescriptor<Position>()) {
            context.delete(position)
        }
        let tokens = [
            PositionToken(role: .balance, amount: 3, usdValue: 9000, asset: eth),
            PositionToken(role: .supply, amount: 4100, usdValue: 4100, asset: usdc)
        ]
        context.insert(Self.position(.idle, [tokens[0]], in: account))
        context.insert(Self.position(.lending, [tokens[1]], in: account))
        try context.save()
        let tokenIDs = Set(tokens.map(\.id))
        #expect(waitUntil { counter.builds >= 1 && counter.last.map { Set($0.inputs.map(\.tokenId)) } == tokenIDs })
        spin(0.5)
        print("C-P count: T6 save builds=\(counter.summary)")
    }

    /// The provider walks the store on the main actor, so it is mounted only on All Positions, its
    /// last reader (#123): Overview builds nothing, and entering All Positions builds once.
    @Test func `only All Positions builds a projection`() throws {
        let suiteName = "ActivePortfolioProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let counter = BuildCounter()
        let dashboard = try Dashboard(section: .overview, counter: counter, defaults: defaults)

        spin(0.5)
        print("C-P count: T7 overview builds=\(counter.summary)")
        #expect(counter.builds == 0, "Overview built the All Positions projection")

        dashboard.store.send(.sectionSelected(.allPositions))
        #expect(waitUntil { counter.builds >= 1 }, "entering All Positions built no projection")
        print("C-P count: T7 navigation builds=\(counter.summary)")
    }

    // MARK: - Hosts

    /// The production `ContentView` as `ViewRenderSmokeTests` hosts it, with the counting builder.
    /// The caller owns `defaults` and removes its domain.
    @MainActor
    private struct Dashboard {
        let store: StoreOf<AppFeature>
        let container: ModelContainer
        let appState = AppState()

        init(section: SidebarSection, counter: BuildCounter, defaults: UserDefaults) throws {
            let smoke = ViewRenderSmokeTests()
            self.container = try smoke.makeContainer()
            self.store = smoke.makeStore(section: section)
            appState.bridge(from: store)
            smoke.render(ContentView(store: store)
                .modelContainer(container)
                .environment(appState)
                .environment(\.activePortfolioBuilder, counter.builder)
                .defaultAppStorage(defaults)
                .frame(width: 1400, height: 900))
        }
    }

    private static func host(_ view: some View) -> NSView {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        retainedWindows.append(window)
        if retainedWindows.count > maxRetainedWindows {
            retainedWindows.removeFirst(retainedWindows.count - maxRetainedWindows)
        }
        return hostingView
    }

    private static func position(_ type: PositionType, _ tokens: [PositionToken], in account: Account) -> Position {
        Position(positionType: type, chain: .ethereum, tokens: tokens, account: account, syncedAt: syncedAt)
    }

    /// Query order is not contractual, so values are compared in ID order.
    private static func sorted(_ portfolio: ActivePortfolioProjection) -> ActivePortfolioProjection {
        ActivePortfolioProjection(
            inputs: portfolio.inputs.sorted { $0.tokenId.uuidString < $1.tokenId.uuidString },
            cards: portfolio.cards.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    /// Spins the main run loop, which is what lets SwiftUI re-evaluate the hosted view.
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

/// Counts the provider's builds and their main-thread CPU time. One per host, never shared.
@MainActor
private final class BuildCounter {
    private(set) var builds = 0
    private(set) var last: ActivePortfolioProjection?
    private var nanoseconds: [UInt64] = []

    var builder: ActivePortfolioBuilder {
        ActivePortfolioBuilder { [self] positions in
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let projection = ActivePortfolioProjection(positions)
            nanoseconds.append(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start)
            builds += 1
            last = projection
            return projection
        }
    }

    var summary: String {
        let milliseconds = nanoseconds.map { String(format: "%.3f", Double($0) / 1_000_000) }
        return "\(builds) cpu-ms=[\(milliseconds.joined(separator: ", "))]"
    }

    func reset() {
        builds = 0
        nanoseconds = []
    }
}

@MainActor
private final class PortfolioRecorder {
    var portfolio = ActivePortfolioProjection(inputs: [], cards: [])
}

private struct PortfolioSink: View {
    @Environment(\.activePortfolio) private var portfolio
    let recorder: PortfolioRecorder

    var body: some View {
        recorder.portfolio = portfolio
        return Text("\(portfolio.cards.count)")
    }
}
