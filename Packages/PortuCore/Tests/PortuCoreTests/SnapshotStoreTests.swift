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

/// Exact tier boundaries, written out by hand rather than derived from the retention code,
/// so any rewrite of the bucket math has something independent to answer to.
struct SnapshotStoreBoundaryTests {
    private let store = SnapshotStore()

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return Self.utcCalendar.date(from: parts)!
    }

    /// Sunday 2026-03-22 12:00 UTC. Seven days earlier is Sunday 2026-03-15 12:00; ninety days
    /// earlier is Monday 2025-12-22 12:00, which puts the 90 day line in the middle of a Monday.
    private var sunday: Date {
        utc(2026, 3, 22, 12)
    }

    /// Wednesday 2026-03-25 12:00 UTC. Ninety days earlier is Thursday 2025-12-25 12:00, in the
    /// middle of the ISO week that starts Monday 2025-12-22.
    private var wednesday: Date {
        utc(2026, 3, 25, 12)
    }

    @Test func `a snapshot exactly seven days old is aged, not recent`() {
        let line = utc(2026, 3, 15, 12)
        let hourBefore = utc(2026, 3, 15, 11)
        // Aged: both sit in the Mar 15 daily bucket, so only the later one survives.
        #expect(store.prune(snapshotDates: [hourBefore, line], now: sunday) == [line])
        // One second newer is recent and kept next to the daily survivor.
        let secondAfter = utc(2026, 3, 15, 12, 0, 1)
        #expect(store.prune(snapshotDates: [line, secondAfter], now: sunday) == [line, secondAfter])
    }

    @Test func `a snapshot exactly ninety days old is daily, one second older is weekly`() {
        let line = utc(2025, 12, 22, 12)
        let secondBefore = utc(2025, 12, 22, 11, 59, 59)
        let earlySameDay = utc(2025, 12, 22, 5)
        let lateSameDay = utc(2025, 12, 22, 18)
        // Same calendar day, different tiers: the line and the second before it do not share a bucket.
        #expect(store.prune(snapshotDates: [secondBefore, line], now: sunday) == [secondBefore, line])
        // The early row shares the weekly bucket of the row just before the line and loses to it.
        #expect(store.prune(snapshotDates: [earlySameDay, secondBefore, line], now: sunday) == [secondBefore, line])
        // The late row shares the daily bucket of the line and beats it.
        #expect(store.prune(snapshotDates: [earlySameDay, secondBefore, line, lateSameDay], now: sunday) == [secondBefore, lateSameDay])
    }

    @Test func `weeks start on Monday`() {
        let sundayNight = utc(2025, 11, 23, 23, 59, 59)
        let mondayMidnight = utc(2025, 11, 24)
        let nextSundayNight = utc(2025, 11, 30, 23, 59, 59)
        // Sunday night and the following Monday midnight are different weeks.
        #expect(store.prune(snapshotDates: [sundayNight, mondayMidnight], now: sunday) == [sundayNight, mondayMidnight])
        // Monday midnight and the end of that same Sunday are one week.
        #expect(store.prune(snapshotDates: [mondayMidnight, nextSundayNight], now: sunday) == [nextSundayNight])
    }

    @Test func `a week that spans New Year is one week`() {
        let july = utc(2026, 7, 1, 12)
        let previousWeek = utc(2025, 12, 28, 23)
        let tuesday = utc(2025, 12, 30, 10)
        let thursday = utc(2026, 1, 1, 10)
        #expect(store.prune(snapshotDates: [previousWeek, tuesday, thursday], now: july) == [previousWeek, thursday])
    }

    @Test func `a week split by the ninety day line keeps a weekly and daily survivors`() {
        let mondayMorning = utc(2025, 12, 22, 9)
        let tuesdayMorning = utc(2025, 12, 23, 9)
        let thursdayAfternoon = utc(2025, 12, 25, 13)
        let fridayMorning = utc(2025, 12, 26, 9)
        let dates = [mondayMorning, tuesdayMorning, thursdayAfternoon, fridayMorning]
        // Monday and Tuesday are older than the line and share one weekly bucket; Thursday and Friday
        // are younger and each get their own daily bucket.
        #expect(store.prune(snapshotDates: dates, now: wednesday) == [tuesdayMorning, thursdayAfternoon, fridayMorning])
    }
}

/// The bucket floor and the newest-first walk that pruning against a database is built on.
struct SnapshotStoreBucketTests {
    private let store = SnapshotStore()

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return Self.utcCalendar.date(from: parts)!
    }

    /// Wednesday 2026-03-25 12:00 UTC: the cutoff is Wednesday 2026-03-18 12:00 and the ninety day
    /// line is Thursday 2025-12-25 12:00, in the middle of the week that starts Monday 2025-12-22.
    private var now: Date {
        utc(2026, 3, 25, 12)
    }

    @Test func `the cutoff is seven days before now`() {
        #expect(store.retentionCutoff(now: now) == utc(2026, 3, 18, 12))
    }

    @Test func `snapshots newer than the cutoff have no bucket`() {
        #expect(store.bucketFloor(of: utc(2026, 3, 18, 12, 0, 1), now: now) == nil)
        #expect(store.bucketFloor(of: now, now: now) == nil)
    }

    @Test func `a daily bucket starts at midnight, the cutoff day included`() {
        #expect(store.bucketFloor(of: utc(2026, 3, 18, 12), now: now) == utc(2026, 3, 18))
        #expect(store.bucketFloor(of: utc(2026, 2, 10, 15, 30), now: now) == utc(2026, 2, 10))
    }

    @Test func `the day holding the ninety day line starts at the line, not at midnight`() {
        let line = utc(2025, 12, 25, 12)
        #expect(store.bucketFloor(of: line, now: now) == line)
        #expect(store.bucketFloor(of: utc(2025, 12, 25, 18), now: now) == line)
    }

    @Test func `a weekly bucket starts on Monday at midnight`() {
        #expect(store.bucketFloor(of: utc(2025, 12, 25, 11, 59, 59), now: now) == utc(2025, 12, 22))
        #expect(store.bucketFloor(of: utc(2025, 11, 30, 23, 59, 59), now: now) == utc(2025, 11, 24))
        #expect(store.bucketFloor(of: utc(2025, 11, 24), now: now) == utc(2025, 11, 24))
    }

    @Test func `walking newest first finds exactly the aged dates prune keeps`() throws {
        // Dates packed around both lines, the cutoff day and a week boundary, plus a spread over a year.
        var dates = [
            utc(2026, 3, 18, 12), utc(2026, 3, 18, 11, 59, 59), utc(2026, 3, 18, 12, 0, 1),
            utc(2025, 12, 25, 12), utc(2025, 12, 25, 11, 59, 59), utc(2025, 12, 25, 12, 0, 1),
            utc(2025, 12, 22), utc(2025, 12, 21, 23, 59, 59), utc(2025, 12, 28, 23, 59, 59),
            utc(2025, 12, 29), utc(2026, 1, 1, 10),
            // Sub-second timestamps just below a bucket start, which real `Date.now` values are.
            utc(2025, 12, 22) - 0.25, utc(2025, 12, 29) - 0.001, utc(2026, 2, 10) - 0.5,
            utc(2025, 12, 25, 12) - 0.5
        ]
        dates += (0 ..< 300).map { now.addingTimeInterval(-Double($0) * 86400 * 1.3 - Double($0 * 977 % 86400)) }
        let walked = try store.agedSurvivors(now: now) { upperBound in
            dates.filter { $0 <= upperBound }.max()
        }
        let aged = store.prune(snapshotDates: dates, now: now).filter { $0 <= store.retentionCutoff(now: now) }
        #expect(walked.sorted() == aged)
    }

    @Test(arguments: 0 ..< 40)
    func `walking finds what prune keeps for random dates and a random now`(seed: Int) throws {
        var state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1
        func next(_ limit: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * limit
        }
        let randomNow = utc(2026, 1, 1) + next(400 * 86400).rounded()
        let dates = (0 ..< 150).map { _ in randomNow - next(500 * 86400).rounded() }
        let walked = try store.agedSurvivors(now: randomNow) { upperBound in
            dates.filter { $0 <= upperBound }.max()
        }
        let aged = store.prune(snapshotDates: dates, now: randomNow).filter { $0 <= store.retentionCutoff(now: randomNow) }
        #expect(walked.sorted() == aged, "seed \(seed)")
    }

    @Test func `a lookup that answers past its bound ends the walk with an error`() {
        // Whatever the walk has not listed gets deleted, so it must not return a short list.
        #expect(throws: SnapshotRetentionError.self) {
            try store.agedSurvivors(now: now) { upperBound in upperBound + 1 }
        }
    }

    @Test func `a lookup that finds nothing ends the walk with no survivors`() throws {
        #expect(try store.agedSurvivors(now: now) { _ in nil }.isEmpty)
    }
}
