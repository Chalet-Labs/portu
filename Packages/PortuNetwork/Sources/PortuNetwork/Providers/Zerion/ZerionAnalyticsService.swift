import Foundation
import PortuCore

public protocol ZerionAnalyticsService: Sendable {
    func fetchPortfolioValueHistory(
        scope: PortfolioAnalyticsScope,
        period: ZerionChartPeriod) async throws -> [ProviderPortfolioValueDTO]

    func fetchPnL(
        scope: PortfolioAnalyticsScope,
        range: ProviderPnLRange,
        currency: FiatCurrency,
        implementations: [OnchainTokenIdentity],
        asOf: Date) async throws -> ProviderPnLDTO

    func fetchPortfolioSummary(
        scope: PortfolioAnalyticsScope) async throws -> ZerionPortfolioSummary
}
