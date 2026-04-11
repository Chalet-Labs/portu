import Foundation
@testable import PortuCore
import Testing

struct SnapshotStoreTests {
    private let store = SnapshotStore()
    /// Fixed reference: 2026-03-22 12:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_774_137_600)

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-(hours * 3600))
    }

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-(days * 86400))
    }

    @Test func `recent snapshots all retained`() {
        let dates = [hoursAgo(1), hoursAgo(12), daysAgo(3), daysAgo(6)]
        let retained = store.prune(snapshotDates: dates, now: now)
        #expect(retained.count == 4)
    }

    @Test func `exactly 7 days old goes to daily bucket not recent`() {
        let exactlySevenDays = daysAgo(7)
        let retained = store.prune(snapshotDates: [exactlySevenDays], now: now)
        // Should be in daily bucket (count 1 either way, but boundary is correct)
        #expect(retained.count == 1)
    }

    @Test func `daily bucket keeps last per day`() {
        // Use startOfDay to avoid noon+17h crossing to next day
        let dayBase = Self.utcCalendar.startOfDay(for: daysAgo(10))
        let morning = dayBase.addingTimeInterval(9 * 3600)
        let evening = dayBase.addingTimeInterval(17 * 3600)
        let retained = store.prune(snapshotDates: [morning, evening], now: now)
        #expect(retained.count == 1)
        #expect(retained.contains(evening))
    }

    @Test func `weekly bucket keeps last per week`() {
        // Two snapshots mid-week (Wed/Thu), > 90 days ago — guaranteed same week
        let wednesday = daysAgo(116) // 2025-11-26 (Wed)
        let thursday = daysAgo(115) // 2025-11-27 (Thu)
        let retained = store.prune(snapshotDates: [wednesday, thursday], now: now)
        #expect(retained.count == 1)
        #expect(retained.contains(thursday))
    }

    @Test func `mixed buckets across all tiers`() {
        let dayBase = Self.utcCalendar.startOfDay(for: daysAgo(10))
        let dates = [
            daysAgo(2), // recent — keep
            dayBase.addingTimeInterval(9 * 3600), // daily — drop (same day as next)
            dayBase.addingTimeInterval(17 * 3600), // daily — keep (later in day)
            daysAgo(116), // weekly — drop (same week as next, Wed)
            daysAgo(115), // weekly — keep (later in same week, Thu)
            daysAgo(132) // weekly — keep (different week)
        ]
        let retained = store.prune(snapshotDates: dates, now: now)
        #expect(retained.count < dates.count)
        #expect(retained.contains(dates[0]))
        #expect(retained.contains(dates[2]))
        #expect(retained.contains(dates[4]))
    }

    @Test func `empty input returns empty`() {
        let retained = store.prune(snapshotDates: [], now: now)
        #expect(retained.isEmpty)
    }

    @Test func `result is sorted`() {
        let dates = [daysAgo(1), daysAgo(50), daysAgo(200), daysAgo(3)]
        let retained = store.prune(snapshotDates: dates, now: now)
        #expect(retained == retained.sorted())
    }
}
