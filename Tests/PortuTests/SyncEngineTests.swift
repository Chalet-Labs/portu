import Testing
import Foundation
import SwiftData
@testable import Portu
import PortuCore

@Suite("SyncEngine Tests")
struct SyncEngineTests {

    private func makeTestContext() throws -> (ModelContext, AppState, SyncEngine) {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let appState = AppState()
        let mockStore = MockSecretStore()
        let engine = SyncEngine(modelContext: context, appState: appState, secretStore: mockStore)
        return (context, appState, engine)
    }

    @Test func syncWithNoAccountsSetsError() async throws {
        let (_, appState, engine) = try makeTestContext()
        await engine.sync()
        if case .error(let msg) = appState.syncStatus {
            #expect(msg.contains("No active accounts"))
        } else {
            Issue.record("Expected .error status, got \(appState.syncStatus)")
        }
    }

    @Test func syncManualOnlyAccountsCreatesSnapshots() async throws {
        let (context, appState, engine) = try makeTestContext()
        let asset = Asset(symbol: "GOLD", name: "Gold Token", category: .other)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 100, usdValue: 5000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 5000, tokens: [token])
        let account = Account(name: "Manual", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        await engine.sync()

        let snapshots = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots[0].totalValue == 5000)
        #expect(snapshots[0].isPartial == false)
        #expect(appState.syncStatus == .idle)
    }

    @Test func snapshotBatchIdsLinkCorrectly() async throws {
        let (context, appState, engine) = try makeTestContext()
        let asset = Asset(symbol: "ETH", name: "Ethereum", category: .crypto)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 10, usdValue: 25000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 25000, tokens: [token])
        let account = Account(name: "Wallet A", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        await engine.sync()

        let portfolioSnaps = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        let accountSnaps = try context.fetch(FetchDescriptor<AccountSnapshot>())
        let assetSnaps = try context.fetch(FetchDescriptor<AssetSnapshot>())

        #expect(portfolioSnaps.count == 1)
        #expect(accountSnaps.count == 1)
        #expect(assetSnaps.count == 1)

        // All three tiers share the same batch ID
        let batchId = portfolioSnaps[0].syncBatchId
        #expect(accountSnaps[0].syncBatchId == batchId)
        #expect(assetSnaps[0].syncBatchId == batchId)

        // AccountSnapshot references the correct account
        #expect(accountSnaps[0].accountId == account.id)

        // AssetSnapshot references the correct asset
        #expect(assetSnaps[0].assetId == asset.id)
        #expect(assetSnaps[0].symbol == "ETH")

        #expect(appState.syncStatus == .idle)
    }
}

// MARK: - MockSecretStore

private final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func get(key: String) throws(KeychainError) -> String? { store[key] }
    func set(key: String, value: String) throws(KeychainError) { store[key] = value }
    func delete(key: String) throws(KeychainError) { store.removeValue(forKey: key) }
}
