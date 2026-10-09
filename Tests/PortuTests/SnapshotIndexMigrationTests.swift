import Foundation
@testable import Portu
import PortuCore
import SQLite3
import SwiftData
import Testing

/// `PreSnapshotIndexes.store` was written by v1.9.4's schema, before the snapshot tables had
/// time-series indexes: three batches of dummy rows (one portfolio, one account and two asset
/// rows each). An index-only change does not move SwiftData's entity hash, so these tests are what
/// proves an existing store really gains the indexes, and keeps its rows, when it is opened.
@MainActor
struct SnapshotIndexMigrationTests {
    @Test func `a store from before the snapshot indexes gains them on open and keeps its rows`() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "PortuSnapshotIndexMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: directory)
        }
        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/PreSnapshotIndexes.store", directoryHint: .notDirectory)
        try fileManager.copyItem(at: fixture, to: storeURL)
        #expect(try snapshotIndexCount(in: storeURL, table: "ZASSETSNAPSHOT") == 0)
        #expect(try snapshotIndexCount(in: storeURL, table: "ZACCOUNTSNAPSHOT") == 0)

        let container = try ModelContainerFactory(storeURL: storeURL).makeForProduction()
        let context = container.mainContext

        #expect(try context.fetchCount(FetchDescriptor<PortfolioSnapshot>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<AccountSnapshot>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<AssetSnapshot>()) == 6)
        #expect(try snapshotIndexCount(in: storeURL, table: "ZASSETSNAPSHOT") == 3)
        #expect(try snapshotIndexCount(in: storeURL, table: "ZACCOUNTSNAPSHOT") == 2)
    }

    /// How many `#Index` indexes SwiftData has built on `table`, leaving out the unique-id one.
    private func snapshotIndexCount(in storeURL: URL, table: String) throws -> Int {
        var database: OpaquePointer?
        // Read-write only because a WAL-mode file with no -shm beside it cannot be opened read-only;
        // this only ever points at the test's own temporary copy.
        guard sqlite3_open_v2(storeURL.path(percentEncoded: false), &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let query = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND tbl_name = '\(table)' AND name LIKE '%SwiftDataIndex%'"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CocoaError(.fileReadUnknown)
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
