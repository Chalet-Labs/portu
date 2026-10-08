import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// Retention as seen through a whole sync: aged snapshots are seeded and saved, a manual-account
/// sync runs, and the surviving timestamps of each table are checked against hand-worked answers.
@MainActor
struct SyncEngineSnapshotRetentionTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    private struct Batch {
        let timestamp: Date
        var hasAssetRows = true
    }

    private struct Survivors: Equatable {
        var portfolio: [Date]
        var account: [Date]
        var asset: [Date]
    }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory().makeInMemory())
    }

    private func makeEngine(_ context: ModelContext) -> SyncEngine {
        SyncEngine(modelContext: context, providerFactory: ProviderFactory(secretStore: InMemorySecretStore()))
    }

    private func insertManualAccount(into context: ModelContext) throws {
        let asset = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 10, usdValue: 25000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 25000, tokens: [token])
        context.insert(Account(name: "Wallet A", kind: .manual, dataSource: .manual, positions: [position]))
        try context.save()
    }

    /// One batch is a portfolio row, an account row, and two asset rows sharing one timestamp.
    private func seed(_ batches: [Batch], into context: ModelContext) throws {
        let accountID = UUID()
        for batch in batches {
            let batchID = UUID()
            context.insert(PortfolioSnapshot(
                syncBatchId: batchID, timestamp: batch.timestamp,
                totalValue: 1, idleValue: 1, deployedValue: 0, debtValue: 0, isPartial: false))
            context.insert(AccountSnapshot(
                syncBatchId: batchID, timestamp: batch.timestamp,
                accountId: accountID, totalValue: 1, isFresh: true))
            guard batch.hasAssetRows else { continue }
            for symbol in ["AAA", "BBB"] {
                context.insert(AssetSnapshot(
                    syncBatchId: batchID, timestamp: batch.timestamp,
                    accountId: accountID, assetId: UUID(), symbol: symbol,
                    category: .other, amount: 1, usdValue: 1))
            }
        }
        try context.save()
    }

    /// The seeded timestamps still present, i.e. everything older than `start`, which is
    /// taken before the sync so the sync's own batch is excluded.
    private func survivors(in context: ModelContext, before start: Date) throws -> Survivors {
        func older(_ dates: [Date]) -> [Date] {
            Set(dates.filter { $0 < start }).sorted()
        }
        return try Survivors(
            portfolio: older(context.fetch(FetchDescriptor<PortfolioSnapshot>()).map(\.timestamp)),
            account: older(context.fetch(FetchDescriptor<AccountSnapshot>()).map(\.timestamp)),
            asset: older(context.fetch(FetchDescriptor<AssetSnapshot>()).map(\.timestamp)))
    }

    private func startOfUTCDay(_ date: Date) -> Date {
        Self.calendar.startOfDay(for: date)
    }

    private func startOfUTCWeek(_ date: Date) -> Date {
        Self.calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    @Test func `sync keeps everything recent, the last batch per day, and the last per week`() async throws {
        let context = try makeContext()
        try insertManualAccount(into: context)
        let start = Date.now

        let recentA = start - 1 * day
        let recentB = start - 3 * day
        let dayBase = startOfUTCDay(start - 20 * day)
        let dayMorning = dayBase + 3 * hour
        let dayEvening = dayBase + 9 * hour
        let weekBase = startOfUTCWeek(start - 120 * day)
        let weekTuesday = weekBase + 1 * day + 10 * hour
        let weekThursday = weekBase + 3 * day + 10 * hour
        let old = start - 200 * day
        try seed(
            [recentA, recentB, dayMorning, dayEvening, weekTuesday, weekThursday, old].map { Batch(timestamp: $0) },
            into: context)

        _ = try await makeEngine(context).sync()

        let expected = [old, weekThursday, dayEvening, recentB, recentA].sorted()
        #expect(try survivors(in: context, before: start) == Survivors(
            portfolio: expected, account: expected, asset: expected))
        // A retained batch keeps all of its rows: two asset rows per timestamp.
        let assetRows = try context.fetch(FetchDescriptor<AssetSnapshot>()).filter { $0.timestamp < start }
        #expect(assetRows.count == expected.count * 2)
    }

    @Test func `an asset-less last batch of a day does not take that day's asset rows with it`() async throws {
        let context = try makeContext()
        try insertManualAccount(into: context)
        let start = Date.now

        let dayBase = startOfUTCDay(start - 20 * day)
        let withAssets = dayBase + 3 * hour
        let withoutAssets = dayBase + 9 * hour
        try seed(
            [Batch(timestamp: withAssets), Batch(timestamp: withoutAssets, hasAssetRows: false)],
            into: context)

        _ = try await makeEngine(context).sync()

        // Each table keeps its own newest row of the day: the portfolio and account tables the
        // asset-less batch, the asset table the earlier batch that still has asset rows.
        #expect(try survivors(in: context, before: start) == Survivors(
            portfolio: [withoutAssets], account: [withoutAssets], asset: [withAssets]))
    }

    /// Pruning deletes in the store directly, and a store-level delete is not named in the
    /// `didSave` of the context. Performance reloads on a save that touches one of the snapshot
    /// entities, and the sync's own save always inserts snapshots, so it still reloads.
    @Test func `the sync's save names the snapshot entities even when it pruned rows`() async throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = ModelContext(container)
        try insertManualAccount(into: context)
        let start = Date.now
        let dayBase = startOfUTCDay(start - 20 * day)
        try seed([Batch(timestamp: dayBase + 3 * hour), Batch(timestamp: dayBase + 9 * hour)], into: context)
        var saves = ModelSaveClient.live(container: container).saves().makeAsyncIterator()

        _ = try await makeEngine(context).sync()

        let event = try #require(await saves.next())
        guard case let .entities(names) = event else {
            Issue.record("Expected the sync's save to name its entities, got \(event).")
            return
        }
        #expect(names.isSuperset(of: ["PortfolioSnapshot", "AccountSnapshot", "AssetSnapshot"]))
        #expect(event.touches(PerformanceDataFetcher.readEntityNames))
        // The earlier batch of that day really was pruned in the same sync.
        #expect(try survivors(in: context, before: start).portfolio == [dayBase + 9 * hour])
    }
}
