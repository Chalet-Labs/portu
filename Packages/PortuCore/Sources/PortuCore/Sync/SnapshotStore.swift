import Foundation

/// Applies bounded snapshot retention by preserving recent, daily, and weekly points.
/// Pure function over dates — no SwiftData dependency.
public struct SnapshotStore: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar? = nil) {
        self.calendar = calendar ?? Self.utcGregorianCalendar
    }

    /// Given a list of snapshot dates, returns the subset that should be retained.
    /// - Snapshots < 7 days old: keep all
    /// - Snapshots 7–90 days old: keep last per day
    /// - Snapshots > 90 days old: keep last per week
    public func prune(snapshotDates: [Date], now: Date = .now) -> [Date] {
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now

        var retainedRecent: [Date] = []
        var dailyBuckets: [Date: Date] = [:]
        var weeklyBuckets: [Date: Date] = [:]

        for snapshotDate in snapshotDates {
            if snapshotDate > sevenDaysAgo {
                retainedRecent.append(snapshotDate)
            } else if snapshotDate >= ninetyDaysAgo {
                let bucket = calendar.startOfDay(for: snapshotDate)
                dailyBuckets[bucket] = max(dailyBuckets[bucket] ?? snapshotDate, snapshotDate)
            } else {
                let bucket = weekBucket(for: snapshotDate)
                weeklyBuckets[bucket] = max(weeklyBuckets[bucket] ?? snapshotDate, snapshotDate)
            }
        }

        return (retainedRecent + dailyBuckets.values + weeklyBuckets.values).sorted()
    }

    private func weekBucket(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}
