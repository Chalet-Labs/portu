import Foundation
import os
import SwiftData

/// Thins the snapshot tables of a `ModelContext` down to what `SnapshotStore` retains.
///
/// Each table is thinned on its own, exactly as `SnapshotStore.prune` would thin that table's own
/// timestamps, but without reading its rows: the newest timestamp of every retention bucket is
/// looked up with one single-row query (indexed, except on the one-row-per-sync portfolio table),
/// and everything older than the cutoff that is not one of those is removed with a single
/// predicated delete in the store.
///
/// The delete is applied to the store at once, not at the context's next `save()`, and it does not
/// appear in the `didSave` notification of that save.
public struct SnapshotPruner: Sendable {
    private let store: SnapshotStore

    private static let signposter = OSSignposter(subsystem: "com.portu.core", category: "SnapshotPruner")

    public init(store: SnapshotStore = SnapshotStore()) {
        self.store = store
    }

    /// Prunes the portfolio, account and asset snapshot tables. Each table is attempted even when
    /// an earlier one fails; the first failure is rethrown at the end.
    public func prune(in context: ModelContext, now: Date = .now) throws {
        let interval = Self.signposter.beginInterval("prune snapshots")
        defer { Self.signposter.endInterval("prune snapshots", interval) }

        let cutoff = store.retentionCutoff(now: now)
        var firstFailure: (any Error)?
        for table in Table.all(in: context) {
            do {
                try prune(table, cutoff: cutoff, now: now)
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    private func prune(_ table: Table, cutoff: Date, now: Date) throws {
        let survivors = try store.agedSurvivors(now: now, newestAtOrBefore: table.newestTimestamp)
        // No survivors means nothing at or before the cutoff, so there is nothing to delete.
        guard !survivors.isEmpty else { return }
        try table.deleteAged(cutoff, survivors)
    }
}

/// The two things pruning needs from a snapshot table. They are written out per model because a
/// `#Predicate` has to name the model's own key paths; a generic one over a shared protocol would
/// build a key path through the protocol that SwiftData cannot map to a stored property.
private struct Table {
    /// The latest timestamp at or before the bound, or nil when the table has none. Reads one row.
    let newestTimestamp: (Date) throws -> Date?
    /// Deletes every row at or before the cutoff whose timestamp is not in the kept list.
    let deleteAged: (_ cutoff: Date, _ keeping: [Date]) throws -> Void

    static func all(in context: ModelContext) -> [Table] {
        [portfolio(in: context), account(in: context), asset(in: context)]
    }

    private static func portfolio(in context: ModelContext) -> Table {
        Table(
            newestTimestamp: { upperBound in
                var descriptor = FetchDescriptor<PortfolioSnapshot>(
                    predicate: #Predicate { $0.timestamp <= upperBound },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                descriptor.fetchLimit = 1
                return try context.fetch(descriptor).first?.timestamp
            },
            deleteAged: { cutoff, keeping in
                try context.delete(
                    model: PortfolioSnapshot.self,
                    where: #Predicate { $0.timestamp <= cutoff && !keeping.contains($0.timestamp) })
            })
    }

    private static func account(in context: ModelContext) -> Table {
        Table(
            newestTimestamp: { upperBound in
                var descriptor = FetchDescriptor<AccountSnapshot>(
                    predicate: #Predicate { $0.timestamp <= upperBound },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                descriptor.fetchLimit = 1
                return try context.fetch(descriptor).first?.timestamp
            },
            deleteAged: { cutoff, keeping in
                try context.delete(
                    model: AccountSnapshot.self,
                    where: #Predicate { $0.timestamp <= cutoff && !keeping.contains($0.timestamp) })
            })
    }

    private static func asset(in context: ModelContext) -> Table {
        Table(
            newestTimestamp: { upperBound in
                var descriptor = FetchDescriptor<AssetSnapshot>(
                    predicate: #Predicate { $0.timestamp <= upperBound },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                descriptor.fetchLimit = 1
                return try context.fetch(descriptor).first?.timestamp
            },
            deleteAged: { cutoff, keeping in
                try context.delete(
                    model: AssetSnapshot.self,
                    where: #Predicate { $0.timestamp <= cutoff && !keeping.contains($0.timestamp) })
            })
    }
}
