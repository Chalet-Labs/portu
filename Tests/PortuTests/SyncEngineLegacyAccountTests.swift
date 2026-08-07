import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

@MainActor
struct SyncEngineLegacyAccountTests {
    @Test func `account scoped sync explains retained legacy Zapper account`() async throws {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self, TokenPricingOverride.self,
            TokenIdentityMapping.self,
            HistoricalPricePoint.self,
            PortfolioCategory.self, CategorySymbolRule.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
            ProviderPortfolioValuePoint.self, ProviderPortfolioHistoryRefresh.self,
            ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let legacy = Account(name: "Legacy", kind: .wallet, dataSource: .zapper)
        context.insert(legacy)
        try context.save()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in LegacySyncStubProvider() }))

        await #expect(throws: SyncError.unsupportedLegacyAccount) {
            _ = try await engine.sync(accountID: legacy.id)
        }
    }
}

private actor LegacySyncStubProvider: PortfolioDataProvider {
    nonisolated let capabilities = ProviderCapabilities()

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        []
    }
}
