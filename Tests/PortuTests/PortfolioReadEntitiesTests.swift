import Foundation
@testable import Portu
import Testing

/// `PortfolioProjector.readEntityNames` and `PortfolioValueChartProjector.readEntityNames` decide
/// which saves rebuild the read model's holdings and its value chart (#123 spec B3, #124 spec C2).
/// A missing entry leaves the dashboard stale until another save, and a stale one rebuilds on
/// unrelated saves, so these tie each list to the app schema and to what its projector fetches.
struct PortfolioReadEntitiesTests {
    /// Schema entities neither build reads. A new model fails the classification test below until
    /// it is added here or to a read list.
    private static let unread: Set<String> = [
        "WalletAddress",
        "AccountSnapshot",
        "ProviderPortfolioValuePoint",
        "ProviderPortfolioHistoryRefresh",
        "ProviderPnLSnapshot",
        "ProviderPnLAssetBreakdown"
    ]

    private static let holdings = PortfolioProjector.readEntityNames
    private static let chart = PortfolioValueChartProjector.readEntityNames

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `every schema entity is read by a build or explicitly not read`() {
        let schema = Set(ModelContainerFactory.schema.entities.map(\.name))

        #expect(Self.unread.isDisjoint(with: Self.holdings))
        #expect(Self.unread.isDisjoint(with: Self.chart))
        #expect(Self.unread == schema.subtracting(Self.holdings).subtracting(Self.chart))
    }

    @Test func `every model the holdings projector fetches is on its read list`() throws {
        let fetched = try fetchedEntities(in: "Sources/Portu/Features/Portfolio/PortfolioProjector.swift")

        #expect(fetched.count == Self.holdings.count, "every read entity is fetched, none only reached")
        #expect(fetched == Self.holdings)
    }

    @Test func `every model the value chart projector fetches is on its read list`() throws {
        let fetched = try fetchedEntities(in: "Sources/Portu/Features/Portfolio/PortfolioValueChartProjector.swift")

        #expect(fetched.count == Self.chart.count, "every read entity is fetched, none only reached")
        #expect(fetched == Self.chart)
    }

    /// A save to any read entity rebuilds after the debounce; a save to an unread one does not.
    @Test(arguments: holdings.sorted())
    func `a save to a holdings entity is one the holdings build follows`(_ name: String) {
        #expect(ModelSaveEvent.entities([name]).touches(Self.holdings))
    }

    @Test(arguments: chart.sorted())
    func `a save to a chart entity is one the chart build follows`(_ name: String) {
        #expect(ModelSaveEvent.entities([name]).touches(Self.chart))
    }

    /// A sync's snapshot save or a rate refresh rebuilds the chart alone.
    @Test(arguments: chart.subtracting(holdings).sorted())
    func `a save only the chart reads is one the holdings build ignores`(_ name: String) {
        #expect(!ModelSaveEvent.entities([name]).touches(Self.holdings))
    }

    @Test(arguments: unread.sorted())
    func `a save to an unread entity is one neither build follows`(_ name: String) {
        #expect(!ModelSaveEvent.entities([name]).touches(Self.holdings))
        #expect(!ModelSaveEvent.entities([name]).touches(Self.chart))
    }

    /// The schema's model types a projector file names in a `FetchDescriptor<…>` or `#Predicate<…>`.
    /// A generic helper's signature (`FetchDescriptor<Model>`) names a placeholder, not an entity.
    private func fetchedEntities(in path: String) throws -> Set<String> {
        let source = try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
        let descriptors = source.matches(of: /FetchDescriptor<\s*(\w+)\s*>/)
        let predicates = source.matches(of: /#Predicate<\s*(\w+)\s*>/)
        let named = Set((descriptors + predicates).map { String($0.output.1) })
        return named.intersection(ModelContainerFactory.schema.entities.map(\.name))
    }
}
