import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

// MARK: - PerformanceDataFetcher Actor Tests

@MainActor
struct PerformanceDataFetcherTests {
    // MARK: - Container / date helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            AssetSnapshot.self,
            Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            ProviderPortfolioValuePoint.self,
            ProviderPortfolioHistoryRefresh.self,
            PortfolioCategory.self,
            CategorySymbolRule.self,
            AccountSnapshot.self,
            PortfolioSnapshot.self,
            HistoricalPricePoint.self,
            CurrencyConversionRatePoint.self,
            TokenPricingOverride.self,
            TokenIdentityMapping.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true)
        ])
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour))!
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    // MARK: - Executor isolation

    @Test func `client factory keeps fetcher execution off main thread`() async throws {
        let container = try makeContainer()
        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)

        #expect(await fetcher.isExecutingOnMainThread() == false)
    }

    // MARK: - Account predicate scope (chartMode: .assets)

    /// Snapshots for two accounts with chartMode .assets: source groups must contain
    /// only the requested account's rows.
    @Test func `account predicate scopes category source groups to selected account`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let accountA = uuid(1)
        let accountB = uuid(2)
        let assetId = uuid(10)
        let day = utcDate(2024, 1, 15, hour: 12)

        ctx.insert(AssetSnapshot(
            syncBatchId: uuid(99), timestamp: day,
            accountId: accountA, assetId: assetId,
            symbol: "ETH", category: .major, amount: 1, usdValue: 2000))
        ctx.insert(AssetSnapshot(
            syncBatchId: uuid(99), timestamp: day,
            accountId: accountB, assetId: assetId,
            symbol: "ETH", category: .major, amount: 5, usdValue: 10000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        // chartMode: .assets is required for categoryChartSource to be populated.
        let request = PerformanceDataRequest(
            accountId: accountA,
            startDate: utcDate(2024, 1, 1),
            chartMode: .assets)

        let snapshot = try await fetcher.load(request)

        let groupAccountIds = Set(snapshot.categoryChartSource.map(\.accountId))
        #expect(
            groupAccountIds == [accountA],
            "Source groups must contain only the requested account's rows")
        #expect(
            !groupAccountIds.contains(accountB),
            "The other account's snapshots must be absent from source groups")
    }

    // MARK: - Date lower bound (startDay predicate)

    /// Snapshot timestamped before utcStartOfDay(startDate) must not appear in source groups.
    @Test func `snapshot before startDay boundary is excluded from category source groups`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)

        // Snapshot on Jan 1; request startDate is Jan 5.
        // utcStartOfDay(Jan 5) = Jan 5 00:00 UTC, so Jan 1 is before the lower bound.
        ctx.insert(AssetSnapshot(
            syncBatchId: uuid(99),
            timestamp: utcDate(2024, 1, 1, hour: 12),
            accountId: account, assetId: uuid(10),
            symbol: "ETH", category: .major, amount: 1, usdValue: 2000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 5),
            chartMode: .assets)

        let snapshot = try await fetcher.load(request)
        #expect(
            snapshot.categoryChartSource.isEmpty,
            "Snapshots before utcStartOfDay(startDate) must not reach source groups")
    }

    /// The shared SQL fetch starts at utcStartOfDay(startDate), but category chart source
    /// preserves the legacy raw startDate boundary after materialization.
    @Test func `snapshot between startDay and startDate is excluded from category source`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)

        // Snapshot at midnight Jan 1 UTC; startDate is noon Jan 1 UTC. The row is
        // available to start-day consumers but must not enter the category chart.
        ctx.insert(AssetSnapshot(
            syncBatchId: uuid(99),
            timestamp: utcDate(2024, 1, 1, hour: 0),
            accountId: account, assetId: uuid(10),
            symbol: "ETH", category: .major, amount: 1, usdValue: 2000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 1, hour: 12),
            chartMode: .assets)

        let snapshot = try await fetcher.load(request)
        #expect(
            snapshot.categoryChartSource.isEmpty,
            "Category chart rows must still satisfy the exact startDate boundary")
    }

    // MARK: - Persisted provider scope gating (chartMode: .value)

    /// With chartMode .value, the value chart includes only the ProviderPortfolioValuePoint
    /// row whose (accountID, scopeFingerprint) matches the request.
    @Test func `value chart includes only provider points matching account and scope fingerprint`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)
        let matchFP = "fp-match"
        let otherFP = "fp-other"
        let jan10 = utcDate(2024, 1, 10)

        ctx.insert(ProviderPortfolioValuePoint(
            accountID: account, scopeFingerprint: matchFP,
            provider: .zerion, coverage: .providerReported,
            timestamp: jan10, usdValue: 5000))
        ctx.insert(ProviderPortfolioValuePoint(
            accountID: account, scopeFingerprint: otherFP,
            provider: .zerion, coverage: .providerReported,
            timestamp: jan10, usdValue: 9999))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 1),
            chartMode: .value,
            analyticsScopeFingerprint: matchFP)

        let snapshot = try await fetcher.load(request)
        #expect(
            !snapshot.valueChart.points.isEmpty,
            "The matching provider point must appear in valueChart.points")
        #expect(
            !snapshot.valueChart.points.contains { $0.value == 9999 },
            "The non-matching scope fingerprint must be excluded from valueChart.points")
    }

    /// When analyticsScopeFingerprint is nil, the fetcher must skip the
    /// ProviderPortfolioValuePoint query (plan item 12).
    @Test func `provider point query is skipped when analytics scope fingerprint is absent`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)

        ctx.insert(ProviderPortfolioValuePoint(
            accountID: account, scopeFingerprint: "some-fp",
            provider: .zerion, coverage: .providerReported,
            timestamp: utcDate(2024, 1, 10), usdValue: 5000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 1),
            chartMode: .value)
        // analyticsScopeFingerprint = nil (default) → provider query skipped.

        let snapshot = try await fetcher.load(request)
        #expect(
            snapshot.valueChart.points.isEmpty,
            "Provider points must not be queried when analyticsScopeFingerprint is nil")
    }

    // MARK: - chartMode gating

    /// With chartMode .value, the category chart source must be [] even when snapshots exist.
    @Test func `categoryChartSource is empty when chartMode is not assets`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)

        ctx.insert(AssetSnapshot(
            syncBatchId: uuid(99),
            timestamp: utcDate(2024, 1, 1, hour: 12),
            accountId: account, assetId: uuid(10),
            symbol: "ETH", category: .major, amount: 1, usdValue: 2000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 1),
            chartMode: .value) // not .assets

        let snapshot = try await fetcher.load(request)
        #expect(
            snapshot.categoryChartSource.isEmpty,
            "categoryChartSource must be [] when chartMode != .assets; fetching it would be wasted work")
    }

    /// With chartMode .assets, the value chart must be .empty even when provider points exist.
    @Test func `valueChart is empty when chartMode is not value`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)

        ctx.insert(ProviderPortfolioValuePoint(
            accountID: account, scopeFingerprint: "fp",
            provider: .zerion, coverage: .providerReported,
            timestamp: utcDate(2024, 1, 10), usdValue: 5000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 1),
            chartMode: .assets, // not .value
            analyticsScopeFingerprint: "fp")

        let snapshot = try await fetcher.load(request)
        #expect(
            snapshot.valueChart == .empty,
            "valueChart must be .empty when chartMode != .value; fetching it would be wasted work")
    }

    // MARK: - Cold entry

    /// An empty store with account + fingerprint must return the empty value-chart sentinel.
    @Test func `cold entry returns empty value chart data without crashing`() async throws {
        let container = try makeContainer()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: uuid(1),
            startDate: utcDate(2024, 1, 1),
            chartMode: .value,
            analyticsScopeFingerprint: "fp")

        let snapshot = try await fetcher.load(request)
        #expect(
            snapshot.valueChart == .empty,
            "An empty store must return PerformanceValueChartData.empty without throwing")
    }

    // MARK: - Category fallback to defaults

    /// Without any PortfolioCategory rows the fetcher falls back to
    /// PortfolioCategoryResolver.defaults so that category toggle buttons are stable.
    @Test func `empty category store falls back to default category set for toggle buttons`() async throws {
        let container = try makeContainer()
        // No PortfolioCategory rows — fetcher must use PortfolioCategoryResolver.defaults.

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: uuid(1),
            startDate: utcDate(2024, 1, 1))

        let snapshot = try await fetcher.load(request)

        let names = snapshot.categories.map(\.name)
        #expect(
            !names.isEmpty,
            "Snapshot categories must be non-empty even when the DB has no PortfolioCategory rows")
        #expect(
            names.contains("ETH"),
            "Default ETH bucket must appear in the fallback category list")
        #expect(
            names.contains("BTC"),
            "Default BTC bucket must appear in the fallback category list")
    }

    // MARK: - Source group structure

    /// Two AssetSnapshot rows for the same (UTC day, account, asset) with different
    /// categories must produce one source group with two distinct candidates — not a
    /// single dedup winner — so that category toggles can reprojected off the main actor.
    @Test func `mid-day category change produces one source group with two candidates`() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = uuid(1)
        let assetId = uuid(10)
        let batch = uuid(99)

        ctx.insert(AssetSnapshot(
            syncBatchId: batch,
            timestamp: utcDate(2024, 1, 1, hour: 8),
            accountId: account, assetId: assetId,
            symbol: "ETH", category: .major,
            amount: 1, usdValue: 2000))
        ctx.insert(AssetSnapshot(
            syncBatchId: batch,
            timestamp: utcDate(2024, 1, 1, hour: 20),
            accountId: account, assetId: assetId,
            symbol: "USDC", category: .stablecoin,
            amount: 2000, usdValue: 2000))
        try ctx.save()

        let fetcher = await PerformanceDataClient.makeFetcher(modelContainer: container)
        let request = PerformanceDataRequest(
            accountId: account,
            startDate: utcDate(2024, 1, 1),
            chartMode: .assets)

        let snapshot = try await fetcher.load(request)

        let group = try #require(
            snapshot.categoryChartSource.first { $0.assetId == assetId },
            "One source group must exist for the asset")
        #expect(group.accountId == account)
        #expect(
            group.candidates.count == 2,
            "Distinct categories in one day must remain separate toggle candidates")
    }
}
