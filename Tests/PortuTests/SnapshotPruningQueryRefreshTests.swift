import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// Views hold every `PortfolioSnapshot` through an unfiltered `@Query` on the main context (the
/// Overview value chart is one). Pruning deletes in the store directly rather than through the
/// context, so those held results only learn about it from the sync's final save. This hosts a
/// real `@Query` and checks that the save after a prune brings it up to date.
@MainActor
struct SnapshotPruningQueryRefreshTests {
    private final class Sink {
        var timestamps: [Date] = []
    }

    private struct HeldSnapshots: View {
        @Query(sort: \PortfolioSnapshot.timestamp) private var snapshots: [PortfolioSnapshot]
        let sink: Sink

        var body: some View {
            sink.timestamps = snapshots.map(\.timestamp)
            return Text("\(snapshots.count)")
        }
    }

    private static var retainedWindows: [NSWindow] = []

    private func spin(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Spins the main run loop, which is what lets SwiftUI re-evaluate the hosted view.
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func insertSnapshot(at timestamp: Date, into context: ModelContext) {
        context.insert(PortfolioSnapshot(
            syncBatchId: UUID(), timestamp: timestamp, totalValue: 1, idleValue: 1,
            deployedValue: 0, debtValue: 0, isPartial: false))
    }

    @Test func `a held query shows the pruned table once the save that follows the prune lands`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let now = Date.now
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let dayBase = utc.startOfDay(for: now - 20 * 86400)
        let kept = dayBase + 9 * 3600
        let recent = now - 3600
        for timestamp in [dayBase + 3 * 3600, dayBase + 6 * 3600, kept, recent] {
            insertSnapshot(at: timestamp, into: context)
        }
        try context.save()

        let sink = Sink()
        let hostingView = NSHostingView(rootView: HeldSnapshots(sink: sink).modelContainer(container))
        hostingView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        Self.retainedWindows.append(window)
        try #require(waitUntil { sink.timestamps.count == 4 }, "the hosted query never loaded the seeded rows")

        // What a sync does: prune, then add the new batch and save.
        try SnapshotPruner().prune(in: context, now: now)
        // The delete went to the store without a save, so the held query has heard nothing yet.
        // This is why the sync has to prune before its final save and not after it.
        spin(for: 0.5)
        #expect(sink.timestamps.count == 4, "the held query already reacted to the prune alone")
        let newest = now
        insertSnapshot(at: newest, into: context)
        try context.save()

        let expected = Set([kept, recent, newest])
        #expect(waitUntil { Set(sink.timestamps) == expected }, "the held query still shows \(sink.timestamps.count) rows")
    }
}
