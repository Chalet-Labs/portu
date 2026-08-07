import Foundation
import SwiftData

@Model
public final class ProviderPortfolioValuePoint {
    #Index<ProviderPortfolioValuePoint>([\.accountID], [\.scopeFingerprint], [\.day])

    @Attribute(.unique) public var cacheKey: String
    public var accountID: UUID
    public var scopeFingerprint: String
    public var provider: PortfolioAnalyticsProvider
    public var coverage: PortfolioAnalyticsCoverage
    public var timestamp: Date
    public var day: Date
    public var usdValue: Decimal
    public var fetchedAt: Date
    public var coverageStartDate: Date

    public init(
        accountID: UUID,
        scopeFingerprint: String,
        provider: PortfolioAnalyticsProvider,
        coverage: PortfolioAnalyticsCoverage,
        timestamp: Date,
        usdValue: Decimal,
        fetchedAt: Date = .now,
        coverageStartDate: Date? = nil) {
        self.cacheKey = Self.cacheKey(
            accountID: accountID,
            scopeFingerprint: scopeFingerprint,
            provider: provider,
            coverage: coverage,
            day: timestamp)
        self.accountID = accountID
        self.scopeFingerprint = scopeFingerprint
        self.provider = provider
        self.coverage = coverage
        self.timestamp = timestamp
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: timestamp)
        self.usdValue = usdValue
        self.fetchedAt = fetchedAt
        self.coverageStartDate = HistoricalPriceCalendar.utcStartOfDay(
            for: coverageStartDate ?? timestamp)
    }

    public static func cacheKey(
        accountID: UUID,
        scopeFingerprint: String,
        provider: PortfolioAnalyticsProvider,
        coverage: PortfolioAnalyticsCoverage,
        day: Date) -> String {
        let seconds = Int(HistoricalPriceCalendar.utcStartOfDay(for: day).timeIntervalSince1970)
        return [
            accountID.uuidString.lowercased(),
            scopeFingerprint,
            provider.rawValue,
            coverage.rawValue,
            String(seconds)
        ].joined(separator: "|")
    }
}
