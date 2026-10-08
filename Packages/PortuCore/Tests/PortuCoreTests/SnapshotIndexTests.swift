import Foundation
@testable import PortuCore
import SQLite3
import SwiftData
import Testing

/// The snapshot tables are read by timestamp range and by account or asset within a range, and
/// pruned by walking timestamps, so the indexes that serve those queries are part of the schema.
struct SnapshotIndexTests {
    private let schema = Schema([PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self])

    /// The key paths of each declared index. SwiftData lists every index as its kind followed by
    /// the property names, e.g. `["binary", "accountId", "timestamp"]`.
    private func declaredIndices(of entity: String) -> Set<[String]> {
        let indices = schema.entities.first { $0.name == entity }?.indices ?? []
        return Set(indices.map { Array($0.dropFirst()) })
    }

    @Test func `asset snapshots are indexed by time, account and time, asset and time`() {
        #expect(declaredIndices(of: "AssetSnapshot") == [
            ["timestamp"], ["accountId", "timestamp"], ["assetId", "timestamp"]
        ])
    }

    @Test func `account snapshots are indexed by time, and account and time`() {
        #expect(declaredIndices(of: "AccountSnapshot") == [
            ["timestamp"], ["accountId", "timestamp"]
        ])
    }

    @Test func `a new store has those indexes in SQLite`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "snapshot-index-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Portu.store")
        let configuration = ModelConfiguration("Portu", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(PortfolioSnapshot(
            syncBatchId: UUID(), timestamp: .now, totalValue: 1, idleValue: 1,
            deployedValue: 0, debtValue: 0, isPartial: false))
        try context.save()

        #expect(try secondaryIndexNames(in: storeURL, table: "ZASSETSNAPSHOT").count == 3)
        #expect(try secondaryIndexNames(in: storeURL, table: "ZACCOUNTSNAPSHOT").count == 2)
    }

    /// Names of the indexes SwiftData builds for `#Index`, as opposed to the unique-id one.
    private func secondaryIndexNames(in storeURL: URL, table: String) throws -> [String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path(percentEncoded: false), &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let query = "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = '\(table)'"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                names.append(String(cString: text))
            }
        }
        return names.filter { $0.contains("SwiftDataIndex") }
    }
}
