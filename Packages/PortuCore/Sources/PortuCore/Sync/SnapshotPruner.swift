import Foundation
import os
import SwiftData

/// Thins the snapshot tables of a `ModelContext` down to what `SnapshotStore` retains.
public struct SnapshotPruner {
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

        var firstFailure: (any Error)?
        do { try pruneTable(PortfolioSnapshot.self, in: context, now: now) } catch { firstFailure = error }
        do { try pruneTable(AccountSnapshot.self, in: context, now: now) } catch { firstFailure = firstFailure ?? error }
        do { try pruneTable(AssetSnapshot.self, in: context, now: now) } catch { firstFailure = firstFailure ?? error }
        if let firstFailure {
            throw firstFailure
        }
    }

    private func pruneTable<T: PersistentModel & Timestamped>(_: T.Type, in context: ModelContext, now: Date) throws {
        let all = try context.fetch(FetchDescriptor<T>())
        let retainedDates = Set(store.prune(snapshotDates: all.map(\.timestamp), now: now))
        for snapshot in all where !retainedDates.contains(snapshot.timestamp) {
            context.delete(snapshot)
        }
    }
}
