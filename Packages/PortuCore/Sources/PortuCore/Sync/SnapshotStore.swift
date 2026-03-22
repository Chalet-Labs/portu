import Foundation

/// Applies bounded snapshot retention by preserving recent, daily, and weekly points.
public struct SnapshotStore: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar? = nil) {
        self.calendar = calendar ?? Self.utcGregorianCalendar
    }

    public func prune(snapshotDates: [Date], now: Date = .now) -> [Date] {
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now

        var retainedRecent: [Date] = []
        var dailyBuckets: [Date: Date] = [:]
        var weeklyBuckets: [Date: Date] = [:]

        for snapshotDate in snapshotDates {
            switch snapshotDate {
            case sevenDaysAgo...:
                retainedRecent.append(snapshotDate)
            case ninetyDaysAgo...:
                let bucket = calendar.startOfDay(for: snapshotDate)
                dailyBuckets[bucket] = max(dailyBuckets[bucket] ?? snapshotDate, snapshotDate)
            default:
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
        return calendar
    }
}
