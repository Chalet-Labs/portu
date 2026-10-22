import Foundation
@testable import Portu
import Testing

/// `PortfolioProjector.readEntityNames` decides which saves rebuild the portfolio read model (#123,
/// spec B3). A missing entry leaves the Sidebar header and the Overview top bar stale until another
/// save, and a stale one rebuilds on unrelated saves, so these tie the list to the app schema and
/// to what the projector fetches.
struct PortfolioReadEntitiesTests {
    /// Schema entities the projection does not read. A new model fails the classification test
    /// below until it is added here or to the read list.
    private static let unread: Set<String> = [
        "WalletAddress",
        "CurrencyConversionRatePoint",
        "PortfolioSnapshot",
        "AccountSnapshot",
        "AssetSnapshot",
        "ProviderPortfolioValuePoint",
        "ProviderPortfolioHistoryRefresh",
        "ProviderPnLSnapshot",
        "ProviderPnLAssetBreakdown"
    ]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `every schema entity is either read or explicitly not read`() {
        let schema = Set(ModelContainerFactory.schema.entities.map(\.name))
        let read = PortfolioProjector.readEntityNames

        #expect(read.isDisjoint(with: Self.unread))
        #expect(read.union(Self.unread) == schema)
    }

    @Test func `every model the projector fetches is on the read list`() throws {
        let source = try String(
            contentsOf: repoRoot.appending(path: "Sources/Portu/Features/Portfolio/PortfolioProjector.swift"),
            encoding: .utf8)
        let descriptors = source.matches(of: /FetchDescriptor<\s*(\w+)\s*>/)
        let predicates = source.matches(of: /#Predicate<\s*(\w+)\s*>/)
        let fetched = Set((descriptors + predicates).map { String($0.output.1) })

        #expect(fetched.count == PortfolioProjector.readEntityNames.count, "every read entity is fetched, none only reached")
        #expect(fetched == PortfolioProjector.readEntityNames)
    }

    /// A save to any read entity rebuilds after the debounce; a save to an unread one does not.
    @Test(arguments: PortfolioProjector.readEntityNames.sorted())
    func `a save to a read entity is one the read model follows`(_ name: String) {
        #expect(ModelSaveEvent.entities([name]).touches(PortfolioProjector.readEntityNames))
    }

    @Test(arguments: unread.sorted())
    func `a save to an unread entity is one the read model ignores`(_ name: String) {
        #expect(!ModelSaveEvent.entities([name]).touches(PortfolioProjector.readEntityNames))
    }
}
