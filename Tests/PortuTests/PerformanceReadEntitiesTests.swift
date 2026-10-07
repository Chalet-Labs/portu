import Foundation
@testable import Portu
import Testing

/// `PerformanceDataFetcher.readEntityNames` decides which saves reload Performance. A stale
/// entry leaves old charts on screen and a missing one reloads on every unrelated save, so
/// these tests tie the list to the app schema and to what the fetcher actually fetches.
struct PerformanceReadEntitiesTests {
    /// Schema entities no Performance load reads. A new model fails the classification test
    /// below until it is added here or to the read list.
    private static let unread: Set<String> = [
        "WalletAddress",
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
        let read = PerformanceDataFetcher.readEntityNames

        #expect(read.isDisjoint(with: Self.unread))
        #expect(read.union(Self.unread) == schema)
    }

    /// The model names a source file fetches. A descriptor whose generic is inferred from its
    /// predicate never spells `FetchDescriptor<Model>`, so `#Predicate<Model>` counts too.
    private static func fetchedModelNames(in source: String) -> Set<String> {
        let descriptors = source.matches(of: /FetchDescriptor<\s*(\w+)\s*>/)
        let predicates = source.matches(of: /#Predicate<\s*(\w+)\s*>/)
        return Set((descriptors + predicates).map { String($0.output.1) })
    }

    @Test func `every model the fetcher fetches is on the read list`() throws {
        let source = try String(
            contentsOf: repoRoot.appending(path: "Sources/Portu/Features/Performance/PerformanceDataFetcher.swift"),
            encoding: .utf8)
        let fetched = Self.fetchedModelNames(in: source)

        #expect(!fetched.isEmpty)
        #expect(fetched.isSubset(of: PerformanceDataFetcher.readEntityNames))
    }

    @Test func `the scan sees fetches however they are spelled`() {
        let source = """
        let plain = try context.fetch(FetchDescriptor<AssetSnapshot>(sortBy: []))
        let wrapped = FetchDescriptor<
            PositionToken
        >()
        let inferred = FetchDescriptor(predicate: #Predicate<Asset> { $0.symbol == "ETH" })
        """

        #expect(Self.fetchedModelNames(in: source) == ["AssetSnapshot", "PositionToken", "Asset"])
    }

    @Test func `models reached through a token's relationships are on the read list`() {
        // `PositionToken.position?.account` is read for account scoping and the active-account
        // filter, but no `FetchDescriptor` names those two models.
        #expect(PerformanceDataFetcher.readEntityNames.isSuperset(of: ["PositionToken", "Position", "Account"]))
    }
}
