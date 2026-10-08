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
        var retained: [Date] = []
        var newestPerBucket: [Date: Date] = [:]

        for snapshotDate in snapshotDates {
            if let floor = bucketFloor(of: snapshotDate, now: now) {
                newestPerBucket[floor] = max(newestPerBucket[floor] ?? snapshotDate, snapshotDate)
            } else {
                retained.append(snapshotDate)
            }
        }

        return (retained + newestPerBucket.values).sorted()
    }

    /// Snapshots newer than this are all kept. Anything at or before it is thinned to the newest
    /// one per bucket.
    func retentionCutoff(now: Date) -> Date {
        calendar.date(byAdding: .day, value: -7, to: now) ?? now
    }

    /// The earliest instant of the retention bucket an aged `date` falls in, or nil for a date
    /// that is still recent. Two dates share a bucket exactly when they share a floor.
    ///
    /// A bucket is a UTC day while the date is at most 90 days old and a week (Monday start)
    /// beyond that. The day that holds the 90 day line is cut at the line, because the earlier
    /// part of that day is already weekly.
    func bucketFloor(of date: Date, now: Date) -> Date? {
        guard date <= retentionCutoff(now: now) else { return nil }
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        if date >= ninetyDaysAgo {
            return max(calendar.startOfDay(for: date), ninetyDaysAgo)
        }
        return weekBucket(for: date)
    }

    /// The newest date of every bucket among the aged snapshots, newest bucket first, without
    /// looking at the dates in between. `newestAtOrBefore` answers "what is the latest snapshot
    /// date at or before this instant?", which a database can do with one indexed lookup, so the
    /// cost is one lookup per bucket instead of one read per snapshot.
    ///
    /// A lookup that answers with a date past the bound it was given breaks the walk's premise.
    /// That ends the walk with an error rather than with a list that may be missing buckets, since
    /// whatever is not in the list gets deleted.
    func agedSurvivors(now: Date, newestAtOrBefore: (Date) throws -> Date?) throws -> [Date] {
        var survivors: [Date] = []
        var upperBound = retentionCutoff(now: now)
        while let newest = try newestAtOrBefore(upperBound) {
            guard newest <= upperBound, let floor = bucketFloor(of: newest, now: now) else {
                throw SnapshotRetentionError.lookupPastBound
            }
            survivors.append(newest)
            upperBound = floor.instantBefore
        }
        return survivors
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

enum SnapshotRetentionError: Error {
    case lookupPastBound
}

private extension Date {
    /// The latest representable instant before this one, so that "at or before" reads as "before".
    var instantBefore: Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.nextDown)
    }
}
