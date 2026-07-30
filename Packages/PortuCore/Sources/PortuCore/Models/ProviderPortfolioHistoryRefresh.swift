import Foundation
import SwiftData

@Model
public final class ProviderPortfolioHistoryRefresh {
    #Index<ProviderPortfolioHistoryRefresh>([\.accountID], [\.scopeFingerprint], [\.coverageStartDate])

    @Attribute(.unique) public var cacheKey: String
    public var accountID: UUID
    public var scopeFingerprint: String
    public var provider: PortfolioAnalyticsProvider
    public var coverageStartDate: Date
    public var fetchedAt: Date

    public init(
        accountID: UUID,
        scopeFingerprint: String,
        provider: PortfolioAnalyticsProvider,
        coverageStartDate: Date,
        fetchedAt: Date) {
        self.cacheKey = Self.cacheKey(
            accountID: accountID,
            scopeFingerprint: scopeFingerprint,
            provider: provider,
            coverageStartDate: coverageStartDate)
        self.accountID = accountID
        self.scopeFingerprint = scopeFingerprint
        self.provider = provider
        self.coverageStartDate = HistoricalPriceCalendar.utcStartOfDay(for: coverageStartDate)
        self.fetchedAt = fetchedAt
    }

    public static func cacheKey(
        accountID: UUID,
        scopeFingerprint: String,
        provider: PortfolioAnalyticsProvider,
        coverageStartDate: Date) -> String {
        let seconds = Int(
            HistoricalPriceCalendar.utcStartOfDay(for: coverageStartDate).timeIntervalSince1970)
        return [
            accountID.uuidString.lowercased(),
            scopeFingerprint,
            provider.rawValue,
            String(seconds)
        ].joined(separator: "|")
    }
}
