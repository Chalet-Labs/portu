import Foundation
@testable import PortuCore
import SwiftData
import Testing

/// Retention buckets are UTC days and Monday-start weeks, so the tests build their dates in UTC
/// whatever time zone the machine running them is in.
private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}()

/// Retention against a real store. The expected survivors come from `SnapshotStore.prune` run over
/// each table's full timestamp list, which is how pruning worked before it was bounded, so these
/// tests pin the result and leave the way it is computed free to change.
struct SnapshotPrunerTests {
    private let store = SnapshotStore()
    private let pruner = SnapshotPruner()
    /// Sunday 2026-03-22 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_774_137_600)
    private let day: TimeInterval = 86400

    /// One sync batch: a portfolio row, an account row and `assets` asset rows, all sharing one
    /// timestamp. Switching rows off models batches that never wrote them, and an asset-only seed
    /// is an orphan.
    private struct Seed {
        var timestamp: Date
        var portfolio = true
        var account = true
        var assets = 2
    }

    private struct Rows: Equatable {
        var portfolio: [Date: Int]
        var account: [Date: Int]
        var asset: [Date: Int]
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self])
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func insert(_ seeds: [Seed], into context: ModelContext) {
        let accountID = UUID()
        for seed in seeds {
            let batchID = UUID()
            if seed.portfolio {
                context.insert(PortfolioSnapshot(
                    syncBatchId: batchID, timestamp: seed.timestamp,
                    totalValue: 1, idleValue: 1, deployedValue: 0, debtValue: 0, isPartial: false))
            }
            if seed.account {
                context.insert(AccountSnapshot(
                    syncBatchId: batchID, timestamp: seed.timestamp,
                    accountId: accountID, totalValue: 1, isFresh: true))
            }
            for index in 0 ..< seed.assets {
                context.insert(AssetSnapshot(
                    syncBatchId: batchID, timestamp: seed.timestamp,
                    accountId: accountID, assetId: UUID(), symbol: "A\(index)",
                    category: .other, amount: 1, usdValue: 1))
            }
        }
    }

    private func rows(in container: ModelContainer) throws -> Rows {
        let context = ModelContext(container)
        func counts(_ dates: [Date]) -> [Date: Int] {
            Dictionary(dates.map { ($0, 1) }, uniquingKeysWith: +)
        }
        return try Rows(
            portfolio: counts(context.fetch(FetchDescriptor<PortfolioSnapshot>()).map(\.timestamp)),
            account: counts(context.fetch(FetchDescriptor<AccountSnapshot>()).map(\.timestamp)),
            asset: counts(context.fetch(FetchDescriptor<AssetSnapshot>()).map(\.timestamp)))
    }

    /// Every row whose timestamp `SnapshotStore.prune` keeps for that table, and no other.
    private func expectedRows(_ before: Rows) -> Rows {
        func kept(_ counts: [Date: Int]) -> [Date: Int] {
            let all = counts.flatMap { Array(repeating: $0.key, count: $0.value) }
            let retained = Set(store.prune(snapshotDates: all, now: now))
            return counts.filter { retained.contains($0.key) }
        }
        return Rows(portfolio: kept(before.portfolio), account: kept(before.account), asset: kept(before.asset))
    }

    private func assertPrunesLikeTheStore(_ seeds: [Seed], _ comment: Comment) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insert(seeds, into: context)
        try context.save()
        let before = try rows(in: container)

        try pruner.prune(in: context, now: now)
        try context.save()

        #expect(try rows(in: container) == expectedRows(before), comment)
    }

    @Test func `an empty store prunes without error`() throws {
        try assertPrunesLikeTheStore([], "empty")
    }

    @Test func `recent batches are all kept and aged ones are thinned per tier`() throws {
        let dayBase = utcCalendar.startOfDay(for: now - 20 * day)
        let weekBase = utcCalendar.dateInterval(of: .weekOfYear, for: now - 120 * day)!.start
        try assertPrunesLikeTheStore([
            Seed(timestamp: now - 3600), Seed(timestamp: now - 2 * day), Seed(timestamp: now - 6 * day),
            Seed(timestamp: dayBase + 3600 * 3), Seed(timestamp: dayBase + 3600 * 9),
            Seed(timestamp: weekBase + day + 3600 * 10), Seed(timestamp: weekBase + 3 * day + 3600 * 10),
            Seed(timestamp: now - 200 * day)
        ], "one seed per tier")
    }

    @Test func `the newest batch of a day without asset rows does not take that day's asset rows with it`() throws {
        let dayBase = utcCalendar.startOfDay(for: now - 20 * day)
        try assertPrunesLikeTheStore([
            Seed(timestamp: dayBase + 3600 * 3),
            Seed(timestamp: dayBase + 3600 * 9, assets: 0)
        ], "asset-less newest batch")
    }

    @Test func `an asset row whose batch has no portfolio row is still thinned like its own table`() throws {
        let dayBase = utcCalendar.startOfDay(for: now - 20 * day)
        try assertPrunesLikeTheStore([
            Seed(timestamp: dayBase + 3600 * 3),
            Seed(timestamp: dayBase + 3600 * 5, portfolio: false, account: false),
            Seed(timestamp: dayBase + 3600 * 9, assets: 0)
        ], "orphan asset timestamp")
    }

    @Test func `timestamps on the seven and ninety day lines and the week edges`() throws {
        let sevenDays = now - 7 * day
        let ninetyDays = now - 90 * day
        var seeds = [-1, 0, 1].flatMap { offset in
            [sevenDays, ninetyDays].map { Seed(timestamp: $0 + TimeInterval(offset)) }
        }
        for weeksBack in stride(from: 14, through: 40, by: 4) {
            let monday = utcCalendar.dateInterval(of: .weekOfYear, for: now - TimeInterval(weeksBack) * 7 * day)!.start
            seeds.append(Seed(timestamp: monday))
            seeds.append(Seed(timestamp: monday - 1))
            seeds.append(Seed(timestamp: monday + 7 * day - 1))
            seeds.append(Seed(timestamp: monday - 0.25))
        }
        try assertPrunesLikeTheStore(seeds, "boundary timestamps")
    }

    @Test func `pruning again changes nothing`() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insert((1 ... 90).map { Seed(timestamp: now - TimeInterval($0) * 6 * 3600) }, into: context)
        try context.save()

        try pruner.prune(in: context, now: now)
        try context.save()
        let once = try rows(in: container)
        try pruner.prune(in: context, now: now)
        try context.save()

        #expect(try rows(in: container) == once)
    }

    @Test func `a pending recent insert survives pruning and is saved with the rest`() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dayBase = utcCalendar.startOfDay(for: now - 20 * day)
        insert([Seed(timestamp: dayBase + 3600 * 3), Seed(timestamp: dayBase + 3600 * 9)], into: context)
        try context.save()
        let pendingTimestamp = now - 60
        insert([Seed(timestamp: pendingTimestamp)], into: context)

        try pruner.prune(in: context, now: now)
        try context.save()

        let after = try rows(in: container)
        #expect(after.portfolio.keys.sorted() == [dayBase + 3600 * 9, pendingTimestamp])
        #expect(after.asset[pendingTimestamp] == 2)
    }

    @Test(arguments: 0 ..< 40)
    func `random stores prune exactly like the store's retention`(seed: Int) throws {
        var generator = SplitMix64(seed: UInt64(seed))
        let count = Int.random(in: 20 ... 120, using: &generator)
        // Odd seeds keep sub-second timestamps, as real syncs produce; even ones use whole seconds,
        // so that distinct batches now and then land on the same timestamp.
        let wholeSeconds = seed.isMultiple(of: 2)
        var seeds: [Seed] = (0 ..< count).map { _ in
            let age = Double.random(in: 0 ..< (400 * 86400), using: &generator)
            return Seed(
                timestamp: now - (wholeSeconds ? age.rounded() : age),
                account: Int.random(in: 0 ..< 10, using: &generator) != 0,
                assets: Int.random(in: 0 ..< 5, using: &generator) == 0 ? 0 : 2)
        }
        for _ in 0 ..< Int.random(in: 0 ... 4, using: &generator) {
            let age = Double.random(in: 0 ..< (400 * 86400), using: &generator)
            seeds.append(Seed(timestamp: now - (wholeSeconds ? age.rounded() : age), portfolio: false, account: false))
        }
        try assertPrunesLikeTheStore(seeds, "seed \(seed)")
    }
}

/// A seedable generator, so a failing random store can be rebuilt from its seed alone.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Pruning must not load the tables it thins, and must leave the store in its final state
/// without waiting for the caller's save.
struct SnapshotPrunerQueryTests {
    private let pruner = SnapshotPruner()
    private let now = Date(timeIntervalSince1970: 1_774_137_600)
    private let day: TimeInterval = 86400

    private static let prunerSource: String = {
        let file = URL(fileURLWithPath: #filePath)
        let source = file
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/PortuCore/Sync/SnapshotPruner.swift")
        return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
    }()

    /// Every `FetchDescriptor<...>(...)` call in `source` whose arguments carry no `predicate:`.
    private func unpredicatedFetches(in source: String) -> [String] {
        var found: [String] = []
        var searchStart = source.startIndex
        while let range = source.range(of: "FetchDescriptor<", range: searchStart ..< source.endIndex) {
            searchStart = range.upperBound
            guard let open = source[range.upperBound...].firstIndex(of: "(") else { break }
            var depth = 0
            var close = open
            for index in source[open...].indices {
                if source[index] == "(" {
                    depth += 1
                }
                if source[index] == ")" {
                    depth -= 1
                }
                if depth == 0 {
                    close = index
                    break
                }
            }
            let call = String(source[range.lowerBound ... close])
            if !call.contains("predicate:") {
                found.append(call)
            }
        }
        return found
    }

    @Test func `the scan flags a fetch without a predicate however it is spelled`() {
        #expect(unpredicatedFetches(in: "try context.fetch(FetchDescriptor<T>())").count == 1)
        #expect(unpredicatedFetches(in: "FetchDescriptor<Foo>(sortBy: [SortDescriptor(\\.a)])").count == 1)
        #expect(unpredicatedFetches(in: "FetchDescriptor<Foo>(predicate: #Predicate { $0.a < b }, sortBy: [])").isEmpty)
        #expect(unpredicatedFetches(in: "var d = FetchDescriptor<Foo>(\n    predicate: p)").isEmpty)
    }

    @Test func `the pruner never builds a fetch without a predicate`() throws {
        try #require(!Self.prunerSource.isEmpty, "SnapshotPruner.swift was not found beside the tests")
        try #require(Self.prunerSource.contains("FetchDescriptor<"), "the scan would pass vacuously")
        #expect(unpredicatedFetches(in: Self.prunerSource).isEmpty)
    }

    @Test func `rows are gone from another context before the pruning context saves`() throws {
        let schema = Schema([PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let dayBase = utcCalendar.startOfDay(for: now - 20 * day)
        for hour in [3.0, 9.0] {
            let timestamp = dayBase + hour * 3600
            let batch = UUID()
            context.insert(PortfolioSnapshot(
                syncBatchId: batch, timestamp: timestamp, totalValue: 1, idleValue: 1,
                deployedValue: 0, debtValue: 0, isPartial: false))
            context.insert(AssetSnapshot(
                syncBatchId: batch, timestamp: timestamp, accountId: UUID(), assetId: UUID(),
                symbol: "A", category: .other, amount: 1, usdValue: 1))
        }
        try context.save()

        try pruner.prune(in: context, now: now)

        // Deliberately no `context.save()`: the delete has to be in the store already.
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<PortfolioSnapshot>()) == 1)
        #expect(try reader.fetchCount(FetchDescriptor<AssetSnapshot>()) == 1)
    }

    @Test func `a store with nothing aged is left alone`() throws {
        let schema = Schema([PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let offsets: [TimeInterval] = [60, 3600, 2 * 86400, 6 * 86400]
        for offset in offsets {
            context.insert(PortfolioSnapshot(
                syncBatchId: UUID(), timestamp: now - offset, totalValue: 1, idleValue: 1,
                deployedValue: 0, debtValue: 0, isPartial: false))
        }
        try context.save()

        try pruner.prune(in: context, now: now)

        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PortfolioSnapshot>()) == 4)
    }
}
