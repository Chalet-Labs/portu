import Foundation
@testable import Portu
import PortuCore
import SQLite3
import SwiftData
import Testing

/// What a failed fetch does to a chart build, and what the long-lived projector sees after a sync's
/// prune (#124, spec C2). SwiftData reads an entity the schema lacks as empty, so a fetch can't fail
/// that way; a table that has gone from the store file under an open store can.
extension PortfolioValueChartProjectorTests {
    /// The seeded store in an SQLite file, as production keeps it, with `table` dropped from the file
    /// while the store is open: every later fetch of that entity fails.
    private static func withStore(droppingTable table: String, _ body: (ModelContainer) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PortfolioValueChartProjectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Portu.store")
        let container = try seededStore(at: url)

        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, "DROP TABLE \(table)", nil, nil, nil) == SQLITE_OK, "the store file has no table \(table)")

        try await body(container)
    }

    /// An empty or short month would be drawn, and cached, as the month: the build fails, and the
    /// reducer keeps the chart it has.
    @Test(arguments: ["ZPORTFOLIOSNAPSHOT", "ZCURRENCYCONVERSIONRATEPOINT"])
    func `a failed snapshot or rate fetch fails the build`(_ table: String) async throws {
        try await Self.withStore(droppingTable: table) { container in
            let projector = await PortfolioValueChartProjectorClient.makeProjector(modelContainer: container)

            await #expect { try await projector.build(Self.request()) } throws: { !($0 is CancellationError) }
        }
    }

    /// The estimate is drawn from the overrides and the closes, or not at all: without the overrides it
    /// would count an ignored asset, and without the closes it has nothing to price. The month itself
    /// is still drawn.
    @Test(arguments: ["ZTOKENPRICINGOVERRIDE", "ZHISTORICALPRICEPOINT"])
    func `a failed override or price fetch leaves the estimate out and keeps the rest`(_ table: String) async throws {
        let healthy = try await Self.build(Self.seededStore())
        #expect(!healthy.estimatedUSD.isEmpty, "the seeded store has an estimate to leave out")

        try await Self.withStore(droppingTable: table) { container in
            let source = try await Self.build(container)

            #expect(source.estimatedUSD.isEmpty)
            // The snapshots of two seeded stores differ in their random IDs only.
            #expect(source.snapshots.map(\.timestamp) == healthy.snapshots.map(\.timestamp))
            #expect(source.snapshots.map(\.totalValueUSD) == healthy.snapshots.map(\.totalValueUSD))
            #expect(source.rates == healthy.rates)
        }
    }

    /// A sync prunes the snapshot tables with deletes the store applies at once, outside any save the
    /// projector hears of. The long-lived projector has already read the first asset day when its first
    /// sync is pruned away, so its next build must read the later one: two syncs on day −20, only the
    /// newer of which retention keeps, and with other amounts.
    @Test func `one long lived projector sees a prune move the estimate's first day`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PortfolioValueChartProjectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try Self.seededStore(at: directory.appendingPathComponent("Portu.store"))
        let context = container.mainContext
        let later = Fixture.noon(-20).addingTimeInterval(3 * 3600)
        context.insert(Self.assetRow(Self.btc, "BTC", at: later, amount: 2, usdValue: 120_000))
        context.insert(Self.assetRow(Self.eth, "ETH", at: later, amount: 4, usdValue: 10000))
        try context.save()
        let client = PortfolioValueChartProjectorClient.live(modelContainer: container)
        let before = try await client.build(Self.request())

        try SnapshotPruner().prune(in: context, now: Self.now)
        let after = try await client.build(Self.request())

        #expect(before.estimatedUSD.allSatisfy { $0.value == 65000 }, "the earlier sync is the day's first row for each asset")
        #expect(!after.estimatedUSD.isEmpty)
        #expect(after.estimatedUSD.allSatisfy { $0.value == 130_000 }, "BTC 2 and ETH 4, from the later sync that is left")
        #expect(after.estimatedUSD.map(\.date) == before.estimatedUSD.map(\.date))
        #expect(after.snapshots == before.snapshots, "the portfolio snapshots, one per day, are all kept")
    }
}
