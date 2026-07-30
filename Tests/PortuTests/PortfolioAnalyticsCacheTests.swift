import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

@MainActor
struct PortfolioAnalyticsCacheTests {
    @Test func `canceled live refreshes do not persist completed provider results`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let scope = makeScope(accountID: UUID(), addressSuffix: "55")
        let historyGate = AnalyticsCancellationGate()
        let pnlGate = AnalyticsCancellationGate()
        let service = CancellationRaceAnalyticsService(
            historyGate: historyGate,
            pnlGate: pnlGate)
        let client = PortfolioAnalyticsClient.live(
            modelContext: context,
            service: service,
            now: { Date(timeIntervalSince1970: 1_704_153_600) })

        let historyTask = Task {
            try await client.refreshHistory(scope, .oneMonth)
        }
        await historyGate.waitUntilStarted()
        historyTask.cancel()
        await historyGate.release()
        await #expect(throws: CancellationError.self) {
            _ = try await historyTask.value
        }
        #expect(try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>()).isEmpty)

        let pnlTask = Task {
            try await client.refreshPnL(
                scope,
                .oneMonth,
                .usd,
                [],
                Date(timeIntervalSince1970: 1_704_153_600))
        }
        await pnlGate.waitUntilStarted()
        pnlTask.cancel()
        await pnlGate.release()
        await #expect(throws: CancellationError.self) {
            _ = try await pnlTask.value
        }
        #expect(try context.fetch(FetchDescriptor<ProviderPnLSnapshot>()).isEmpty)
    }

    @Test func `history upsert keeps latest logical day and prunes to 400 day horizon`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accountID = UUID()
        let asOf = Date(timeIntervalSince1970: 1_735_689_600)
        let scope = PortfolioAnalyticsScope(
            accountID: accountID,
            dataSource: .zerion,
            addresses: [.init(
                family: .evm,
                value: "0x1111111111111111111111111111111111111111")])
        let points = (0 ..< 402).map { offset in
            ProviderPortfolioValueDTO(
                timestamp: asOf.addingTimeInterval(TimeInterval(-offset * 86400)),
                usdValue: Decimal(offset),
                provider: .zerion,
                coverage: .providerReported)
        }

        let first = try PortfolioAnalyticsCacheWriter.upsertHistory(
            points,
            scope: scope,
            in: context,
            fetchedAt: asOf)
        let corrected = ProviderPortfolioValueDTO(
            timestamp: asOf.addingTimeInterval(3600),
            usdValue: 999,
            provider: .zerion,
            coverage: .providerReported)
        let second = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [corrected],
            scope: scope,
            in: context,
            fetchedAt: asOf.addingTimeInterval(3600))
        let rows = try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>(
            sortBy: [SortDescriptor(\.day)]))

        #expect(first.inserted == 402)
        #expect(first.pruned == 2)
        #expect(second.updated == 1)
        #expect(rows.count == 400)
        #expect(rows.last?.usdValue == 999)
    }

    @Test func `history upsert replaces same day when provider coverage changes`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let scope = makeScope(accountID: UUID(), addressSuffix: "44")
        let day = Date(timeIntervalSince1970: 1_704_067_200)

        _ = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [.init(
                timestamp: day,
                usdValue: 100,
                provider: .zerion,
                coverage: .noFilter)],
            scope: scope,
            in: context,
            fetchedAt: day)
        _ = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [.init(
                timestamp: day.addingTimeInterval(3600),
                usdValue: 110,
                provider: .zerion,
                coverage: .providerReported)],
            scope: scope,
            in: context,
            fetchedAt: day.addingTimeInterval(3600))

        let rows = try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>())
        #expect(rows.count == 1)
        #expect(rows.first?.coverage == .providerReported)
        #expect(rows.first?.usdValue == 110)
    }

    @Test func `history freshness is scoped to the requested chart coverage`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let scope = makeScope(accountID: UUID(), addressSuffix: "66")
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let staleFetchedAt = now.addingTimeInterval(-2 * ProviderPnLFreshness.freshTTL)
        let longStart = ChartTimeRange.oneYear.startDate(at: now)
        let shortStart = ChartTimeRange.oneWeek.startDate(at: now)
        _ = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [
                .init(
                    timestamp: longStart,
                    usdValue: 80,
                    provider: .zerion,
                    coverage: .providerReported),
                .init(
                    timestamp: now,
                    usdValue: 100,
                    provider: .zerion,
                    coverage: .providerReported)
            ],
            scope: scope,
            in: context,
            fetchedAt: staleFetchedAt,
            coverageStartDate: longStart)
        _ = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [.init(
                timestamp: now,
                usdValue: 110,
                provider: .zerion,
                coverage: .providerReported)],
            scope: scope,
            in: context,
            fetchedAt: now,
            coverageStartDate: shortStart)
        let client = PortfolioAnalyticsClient.live(
            modelContext: context,
            service: CancellationRaceAnalyticsService(
                historyGate: AnalyticsCancellationGate(),
                pnlGate: AnalyticsCancellationGate()),
            now: { now })

        let shortCache = try await client.loadCache(scope, .oneMonth, .usd, shortStart)
        let longCache = try await client.loadCache(scope, .oneMonth, .usd, longStart)

        #expect(shortCache.historyFetchedAt == now)
        #expect(longCache.historyFetchedAt == staleFetchedAt)
    }

    @Test func `scope invalidation does not touch another account`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstScope = makeScope(accountID: UUID(), addressSuffix: "11")
        let secondScope = makeScope(accountID: UUID(), addressSuffix: "22")
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let point = ProviderPortfolioValueDTO(
            timestamp: day,
            usdValue: 100,
            provider: .zerion,
            coverage: .providerReported)
        _ = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [point],
            scope: firstScope,
            in: context,
            fetchedAt: day)
        _ = try PortfolioAnalyticsCacheWriter.upsertHistory(
            [point],
            scope: secondScope,
            in: context,
            fetchedAt: day)

        let removed = try PortfolioAnalyticsCacheWriter.invalidateObsoleteScopes(
            accountID: firstScope.accountID,
            keeping: "replacement",
            in: context)
        let rows = try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>())

        #expect(removed == 1)
        #expect(rows.map(\.accountID) == [secondScope.accountID])
    }

    @Test func `pnl upsert replaces last success and its breakdown`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let scope = makeScope(accountID: UUID(), addressSuffix: "33")
        let first = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            assets: [.init(implementationID: "ethereum:", totalGain: 5)],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let second = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 20,
            assets: [.init(implementationID: "base:", totalGain: 8)],
            fetchedAt: Date(timeIntervalSince1970: 1_700_001_000))

        try PortfolioAnalyticsCacheWriter.upsertPnL(first, scope: scope, in: context)
        try PortfolioAnalyticsCacheWriter.upsertPnL(second, scope: scope, in: context)
        let snapshots = try context.fetch(FetchDescriptor<ProviderPnLSnapshot>())
        let children = try context.fetch(FetchDescriptor<ProviderPnLAssetBreakdown>())

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.totalGain == 20)
        #expect(children.map(\.implementationID) == ["base:"])
    }

    @Test func `clear removes only target analytics and preserves portfolio data`() throws {
        let container = try makeFullContainer()
        let context = container.mainContext
        let target = Account(name: "Target", kind: .wallet, dataSource: .zerion)
        let other = Account(name: "Other", kind: .wallet, dataSource: .zerion)
        let position = Position(
            positionType: .idle,
            netUSDValue: 100,
            account: target)
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let batchID = UUID()
        context.insert(target)
        context.insert(other)
        context.insert(position)
        context.insert(PortfolioSnapshot(
            syncBatchId: batchID,
            timestamp: day,
            totalValue: 100,
            idleValue: 100,
            deployedValue: 0,
            debtValue: 0,
            isPartial: false))
        context.insert(AccountSnapshot(
            syncBatchId: batchID,
            timestamp: day,
            accountId: target.id,
            totalValue: 100,
            isFresh: true))
        context.insert(HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            usdPrice: 40000))
        context.insert(CurrencyConversionRatePoint(
            baseCurrency: .usd,
            quoteCurrency: .chf,
            day: day,
            rate: 0.9))
        insertAnalytics(accountID: target.id, scopeFingerprint: "target", in: context)
        insertAnalytics(accountID: other.id, scopeFingerprint: "other", in: context)
        try context.save()

        let removed = try PortfolioAnalyticsCacheWriter.clear(
            accountID: target.id,
            in: context)

        #expect(removed == 2)
        #expect(try context.fetch(FetchDescriptor<ProviderPortfolioValuePoint>())
            .map(\.accountID) == [other.id])
        #expect(try context.fetch(FetchDescriptor<ProviderPnLSnapshot>())
            .map(\.accountID) == [other.id])
        #expect(try context.fetch(FetchDescriptor<Account>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<HistoricalPricePoint>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CurrencyConversionRatePoint>()).count == 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ProviderPortfolioValuePoint.self,
            ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func makeFullContainer() throws -> ModelContainer {
        let schema = Schema([
            Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            TokenPricingOverride.self,
            TokenIdentityMapping.self,
            HistoricalPricePoint.self,
            CurrencyConversionRatePoint.self,
            ProviderPortfolioValuePoint.self,
            ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self,
            PortfolioCategory.self,
            CategorySymbolRule.self,
            PortfolioSnapshot.self,
            AccountSnapshot.self,
            AssetSnapshot.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func insertAnalytics(
        accountID: UUID,
        scopeFingerprint: String,
        in context: ModelContext) {
        context.insert(ProviderPortfolioValuePoint(
            accountID: accountID,
            scopeFingerprint: scopeFingerprint,
            provider: .zerion,
            coverage: .providerReported,
            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
            usdValue: 100))
        context.insert(ProviderPnLSnapshot(
            accountID: accountID,
            scopeFingerprint: scopeFingerprint,
            provider: .zerion,
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: Date(timeIntervalSince1970: 1_704_067_200)))
    }

    private func makeScope(accountID: UUID, addressSuffix: String) -> PortfolioAnalyticsScope {
        PortfolioAnalyticsScope(
            accountID: accountID,
            dataSource: .zerion,
            addresses: [.init(
                family: .evm,
                value: "0x\(String(repeating: "0", count: 38))\(addressSuffix)")])
    }
}

private actor AnalyticsCancellationGate {
    private var didStart = false
    private var didRelease = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitIgnoringCancellation() async {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        if didRelease == false {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
    }
}

private struct CancellationRaceAnalyticsService: ZerionAnalyticsService {
    let historyGate: AnalyticsCancellationGate
    let pnlGate: AnalyticsCancellationGate

    func fetchPortfolioValueHistory(
        scope _: PortfolioAnalyticsScope,
        period _: ZerionChartPeriod) async throws -> [ProviderPortfolioValueDTO] {
        await historyGate.waitIgnoringCancellation()
        return [.init(
            timestamp: Date(timeIntervalSince1970: 1_704_153_600),
            usdValue: 100,
            provider: .zerion,
            coverage: .noFilter)]
    }

    func fetchPnL(
        scope _: PortfolioAnalyticsScope,
        range: ProviderPnLRange,
        currency: FiatCurrency,
        implementations _: [OnchainTokenIdentity],
        asOf: Date) async throws -> ProviderPnLDTO {
        await pnlGate.waitIgnoringCancellation()
        return ProviderPnLDTO(
            range: range,
            currency: currency,
            totalGain: 10,
            fetchedAt: asOf)
    }

    func fetchPortfolioSummary(
        scope _: PortfolioAnalyticsScope) async throws -> ZerionPortfolioSummary {
        fatalError("Unused in cancellation race tests")
    }
}
