import Foundation
import Testing
@testable import PortuCore

@Suite("Snapshot Store Tests")
struct SnapshotStoreTests {
    @Test func snapshotStorePrunesDailyAndWeeklyBuckets() throws {
        let store = SnapshotStore()
        let now = Date(timeIntervalSince1970: 1_774_137_600) // 2026-03-22 12:00:00 UTC
        let sampleDates = [
            now.addingTimeInterval(-(2 * 24 * 60 * 60)),
            now.addingTimeInterval(-(10 * 24 * 60 * 60) + (9 * 60 * 60)),
            now.addingTimeInterval(-(10 * 24 * 60 * 60) + (17 * 60 * 60)),
            now.addingTimeInterval(-(120 * 24 * 60 * 60)),
            now.addingTimeInterval(-(118 * 24 * 60 * 60)),
            now.addingTimeInterval(-(132 * 24 * 60 * 60)),
        ]

        let pruned = store.prune(snapshotDates: sampleDates, now: now)

        #expect(pruned.count < sampleDates.count)
        #expect(pruned.contains(sampleDates[0]))
        #expect(pruned.contains(sampleDates[2]))
        #expect(pruned.contains(sampleDates[4]))
    }
}
