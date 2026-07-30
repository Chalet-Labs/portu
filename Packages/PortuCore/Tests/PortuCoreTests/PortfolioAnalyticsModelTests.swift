import Foundation
@testable import PortuCore
import SwiftData
import Testing

struct PortfolioAnalyticsDTOTests {
    @Test func `scope normalizes addresses and builds deterministic fingerprint`() throws {
        let accountID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let first = PortfolioAnalyticsScope(
            accountID: accountID,
            dataSource: .zerion,
            addresses: [
                PortfolioAnalyticsAddress(family: .solana, value: " SoLCase "),
                PortfolioAnalyticsAddress(family: .evm, value: " 0xABCDEF "),
                PortfolioAnalyticsAddress(family: .evm, value: "0xabcdef")
            ],
            chainIDs: ["base", "ethereum", "base"])
        let second = PortfolioAnalyticsScope(
            accountID: accountID,
            dataSource: .zerion,
            addresses: [
                PortfolioAnalyticsAddress(family: .evm, value: "0xabcdef"),
                PortfolioAnalyticsAddress(family: .solana, value: "SoLCase")
            ],
            chainIDs: ["ethereum", "base"])

        #expect(first.addresses == [
            PortfolioAnalyticsAddress(family: .evm, value: "0xabcdef"),
            PortfolioAnalyticsAddress(family: .solana, value: "SoLCase")
        ])
        #expect(first.chainIDs == ["base", "ethereum"])
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.fingerprint.isEmpty == false)
    }

    @Test func `scope identity preserves Solana case`() {
        let upper = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [PortfolioAnalyticsAddress(family: .solana, value: "SoLCase")])
        let lower = PortfolioAnalyticsScope(
            accountID: upper.accountID,
            dataSource: .zerion,
            addresses: [PortfolioAnalyticsAddress(family: .solana, value: "solcase")])

        #expect(upper.fingerprint != lower.fingerprint)
    }

    @Test func `analytics values are sendable`() {
        let point = ProviderPortfolioValueDTO(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            usdValue: 100,
            provider: .zerion,
            coverage: .providerReported)
        let pnl = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_100))

        let sendablePoint: any Sendable = point
        let sendablePnL: any Sendable = pnl
        #expect(sendablePoint is ProviderPortfolioValueDTO)
        #expect(sendablePnL is ProviderPnLDTO)
    }

    @Test func `pnl normalizes duplicate exclusions and assets deterministically`() {
        let first = ProviderPnLAssetDTO(implementationID: "ethereum:0xabc", totalGain: 1)
        let replacement = ProviderPnLAssetDTO(implementationID: "ethereum:0xabc", totalGain: 2)
        let other = ProviderPnLAssetDTO(implementationID: "base:0xdef", totalGain: 3)

        let pnl = ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 6,
            excludedIdentifiers: ["zeta", "alpha", "zeta"],
            assets: [first, other, replacement],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(pnl.excludedIdentifiers == ["alpha", "zeta"])
        #expect(pnl.assets.map(\.implementationID) == ["base:0xdef", "ethereum:0xabc"])
        #expect(pnl.assets.last?.totalGain == 2)
    }

    @Test(arguments: [
        (TimeInterval(86399), ProviderPnLFreshness.fresh),
        (TimeInterval(86400), ProviderPnLFreshness.stale),
        (TimeInterval(2_591_999), ProviderPnLFreshness.stale),
        (TimeInterval(2_592_000), ProviderPnLFreshness.expired)
    ])
    func `pnl freshness follows ttl`(age: TimeInterval, expected: ProviderPnLFreshness) {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(ProviderPnLFreshness.evaluate(fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(age)) == expected)
    }
}

@MainActor
struct PortfolioAnalyticsPersistenceTests {
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

    @Test func `portfolio point normalizes day and derives flat cache key`() throws {
        let rawDate = Date(timeIntervalSince1970: 1_704_110_456)
        let point = try ProviderPortfolioValuePoint(
            accountID: #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            scopeFingerprint: "scope",
            provider: .zerion,
            coverage: .providerReported,
            timestamp: rawDate,
            usdValue: 123)

        #expect(point.day == HistoricalPriceCalendar.utcStartOfDay(for: rawDate))
        #expect(point.cacheKey == ProviderPortfolioValuePoint.cacheKey(
            accountID: point.accountID,
            scopeFingerprint: "scope",
            provider: .zerion,
            coverage: .providerReported,
            day: rawDate))
    }

    @Test func `pnl initializer defaults optional metrics and children`() {
        let snapshot = ProviderPnLSnapshot(
            accountID: UUID(),
            scopeFingerprint: "scope",
            provider: .zerion,
            range: .oneMonth,
            currency: .chf,
            totalGain: 10,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.realizedGain == nil)
        #expect(snapshot.unrealizedGain == nil)
        #expect(snapshot.excludedIdentifiers.isEmpty)
        #expect(snapshot.assetBreakdowns.isEmpty)
    }

    @Test func `pnl exclusions persist as a sorted unique list`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let snapshot = ProviderPnLSnapshot(
            accountID: UUID(),
            scopeFingerprint: "scope",
            provider: .zerion,
            range: .oneMonth,
            currency: .usd,
            totalGain: 10,
            excludedIdentifiers: ["zeta", "alpha", "zeta"],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(snapshot)
        try context.save()

        let persisted = try #require(context.fetch(FetchDescriptor<ProviderPnLSnapshot>()).first)
        #expect(persisted.excludedIdentifiers == ["alpha", "zeta"])
    }

    @Test func `pnl cache identity isolates currency and range`() {
        let accountID = UUID()
        let usd = ProviderPnLSnapshot.cacheKey(
            accountID: accountID,
            scopeFingerprint: "scope",
            provider: .zerion,
            range: .oneMonth,
            currency: .usd)
        let chf = ProviderPnLSnapshot.cacheKey(
            accountID: accountID,
            scopeFingerprint: "scope",
            provider: .zerion,
            range: .oneMonth,
            currency: .chf)
        let year = ProviderPnLSnapshot.cacheKey(
            accountID: accountID,
            scopeFingerprint: "scope",
            provider: .zerion,
            range: .oneYear,
            currency: .usd)

        #expect(usd != chf)
        #expect(usd != year)
    }

    @Test func `deleting pnl snapshot cascades asset breakdowns`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let child = ProviderPnLAssetBreakdown(
            implementationID: "ethereum:0xabc",
            totalGain: 5)
        let snapshot = ProviderPnLSnapshot(
            accountID: UUID(),
            scopeFingerprint: "scope",
            provider: .zerion,
            range: .allTime,
            currency: .usd,
            totalGain: 10,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            assetBreakdowns: [child])
        context.insert(snapshot)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ProviderPnLAssetBreakdown>()).count == 1)

        context.delete(snapshot)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ProviderPnLAssetBreakdown>()).isEmpty)
    }
}
