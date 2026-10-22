import ComposableArchitecture
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// What the dashboard's portfolio readers and the provider hold, read through `Mirror`. A position
/// query owned by a view re-fetches and re-faults the store on every body pass of that view; the
/// stall the U8 probe measured was two of them walking the same portfolio. Since #123 the Sidebar
/// header and the Overview top bar read only the portfolio reducer's state.
@MainActor
struct ActivePortfolioStructureTests {
    private typealias PositionQuery = Query<Position, [Position]>
    private typealias TokenQuery = Query<PositionToken, [PositionToken]>
    private typealias OverrideQuery = Query<TokenPricingOverride, [TokenPricingOverride]>

    private static var sliceViews: [(name: String, view: Any)] {
        let store = StoreOf<PortfolioFeature>(initialState: PortfolioFeature.State()) { PortfolioFeature() }
        return [
            ("SidebarPortfolioHeader", SidebarPortfolioHeader(store: store)),
            ("OverviewTopBar", OverviewTopBar(store: store))
        ]
    }

    @Test func `the sidebar header and top bar render only from the portfolio reducer`() {
        for slice in Self.sliceViews {
            let properties = Self.properties(of: slice.view)
            let names = properties.map { String(describing: type(of: $0)) }
            #expect(properties.contains { $0 is StoreOf<PortfolioFeature> }, "\(slice.name): the walk never reached its store")
            #expect(!names.contains { $0.hasPrefix("Query<") }, "\(slice.name): \(names)")
            #expect(!names.contains { $0.hasPrefix("AppStorage<") }, "\(slice.name): \(names)")
            #expect(!names.contains { $0.hasPrefix("Environment<") }, "\(slice.name): \(names)")
            #expect(!properties.contains { $0 is ValuationSources }, "\(slice.name): \(names)")
        }
    }

    @Test func `the All Positions page owns no position or token query and reads the shared projection`() {
        let properties = Self.properties(of: AllPositionsView())
        // The walk reaches `ValuationSources`' own queries, so a nested query cannot hide.
        #expect(properties.contains { $0 is OverrideQuery }, "the walk never reached ValuationSources")
        let owned = properties.filter { $0 is PositionQuery || $0 is TokenQuery }
        #expect(owned.isEmpty, "AllPositionsView owns \(owned.map { type(of: $0) })")
        #expect(properties.count { $0 is Environment<ActivePortfolioProjection> } == 1)
    }

    @Test func `the provider reads no app state`() {
        let properties = Self.properties(of: ActivePortfolioProvider { EmptyView() })
        let queries = properties.filter { String(describing: type(of: $0)).hasPrefix("Query<") }

        #expect(!properties.contains { $0 is Environment<AppState> })
        #expect(!properties.contains { String(describing: type(of: $0)).hasPrefix("AppStorage<") })
        #expect(queries.count == 1)
        #expect(queries.allSatisfy { $0 is PositionQuery })
    }

    /// No provider sits above the dashboard: `HistoricalPricesProvider` fixes its close window when it
    /// is built, so it stays in `DashboardView`, which every navigation click rebuilds, and
    /// `ActivePortfolioProvider` is mounted inside the All Positions branch only. That it builds only
    /// there is pinned by `ActivePortfolioProviderTests`' build counts.
    @Test func `no portfolio provider sits above the dashboard`() {
        let store = ViewRenderSmokeTests().makeStore(section: .allPositions)
        let content = ContentView(store: store, secretStore: InMemorySecretStore()).body
        let dashboard = DashboardView(store: store, secretStore: InMemorySecretStore()).body
        let contentTree = [content] + Self.properties(of: content)
        let dashboardTree = [dashboard] + Self.properties(of: dashboard)
        let count = { (tree: [Any], prefix: String) in
            tree.count { String(describing: type(of: $0)).hasPrefix(prefix) }
        }

        // The walk reaches the dashboard `ContentView` mounts, so a provider around it would show.
        #expect(count(contentTree, "DashboardView") == 1)
        #expect(count(contentTree, "ActivePortfolioProvider<") == 0)
        #expect(count(contentTree, "HistoricalPricesProvider<") == 0)
        #expect(count(dashboardTree, "HistoricalPricesProvider<") == 1)
    }

    /// Every stored property of `value` and of the structs it holds, down to `depth` levels. A
    /// SwiftUI wrapper (`Query`, `Environment`, `AppStorage`, `State`) is reported and not opened;
    /// class instances are never opened.
    static func properties(of value: Any, depth: Int = 6) -> [Any] {
        guard depth > 0 else { return [] }
        return Mirror(reflecting: value).children.flatMap { child -> [Any] in
            let mirror = Mirror(reflecting: child.value)
            let name = String(describing: type(of: child.value))
            let isWrapper = ["Query<", "Environment<", "AppStorage<", "State<"].contains { name.hasPrefix($0) }
            guard !isWrapper, mirror.displayStyle == .struct else { return [child.value] }
            return [child.value] + properties(of: child.value, depth: depth - 1)
        }
    }
}
