@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// What the dashboard's position readers and the provider hold, read through `Mirror`. A position
/// query owned by a view re-fetches and re-faults the store on every body pass of that view; the
/// stall the U8 probe measured was two of them walking the same portfolio.
@MainActor
struct ActivePortfolioStructureTests {
    private typealias PositionQuery = Query<Position, [Position]>
    private typealias TokenQuery = Query<PositionToken, [PositionToken]>
    private typealias OverrideQuery = Query<TokenPricingOverride, [TokenPricingOverride]>

    private static var readers: [(name: String, view: Any)] {
        [
            ("SidebarPortfolioHeader", SidebarPortfolioHeader()),
            ("OverviewTopBar", OverviewTopBar()),
            ("AllPositionsView", AllPositionsView())
        ]
    }

    @Test func `the sidebar header, top bar and All Positions page own no position or token query`() {
        for reader in Self.readers {
            let properties = Self.properties(of: reader.view)
            // The walk reaches `ValuationSources`' own queries, so a nested query cannot hide.
            #expect(properties.contains { $0 is OverrideQuery }, "\(reader.name): the walk never reached ValuationSources")
            let owned = properties.filter { $0 is PositionQuery || $0 is TokenQuery }
            #expect(owned.isEmpty, "\(reader.name) owns \(owned.map { type(of: $0) })")
        }
    }

    @Test func `the sidebar header, top bar and All Positions page read the shared projection`() {
        for reader in Self.readers {
            let properties = Self.properties(of: reader.view)
            #expect(properties.count { $0 is Environment<ActivePortfolioProjection> } == 1, "\(reader.name)")
        }
    }

    @Test func `the provider reads no app state`() {
        let properties = Self.properties(of: ActivePortfolioProvider { EmptyView() })
        let queries = properties.filter { String(describing: type(of: $0)).hasPrefix("Query<") }

        #expect(!properties.contains { $0 is Environment<AppState> })
        #expect(!properties.contains { String(describing: type(of: $0)).hasPrefix("AppStorage<") })
        #expect(queries.count == 1)
        #expect(queries.allSatisfy { $0 is PositionQuery })
    }

    /// `HistoricalPricesProvider` fixes its close window when it is built, so it must sit in
    /// `DashboardView`, which every navigation click rebuilds, and not above it in `ContentView`.
    @Test func `the historical prices provider sits below the content view`() {
        let store = ViewRenderSmokeTests().makeStore(section: .overview)
        let content = ContentView(store: store, secretStore: InMemorySecretStore()).body
        let dashboard = DashboardView(store: store, secretStore: InMemorySecretStore()).body
        let contentTree = [content] + Self.properties(of: content)
        let dashboardTree = [dashboard] + Self.properties(of: dashboard)
        let providers = { (tree: [Any]) in
            tree.count { String(describing: type(of: $0)).hasPrefix("HistoricalPricesProvider<") }
        }

        // The walk reaches the provider `ContentView` does mount, so a provider beside it would show.
        #expect(contentTree.contains { String(describing: type(of: $0)).hasPrefix("ActivePortfolioProvider<") })
        #expect(providers(contentTree) == 0)
        #expect(providers(dashboardTree) == 1)
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
