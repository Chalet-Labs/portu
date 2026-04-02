import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct SyncEngineTests {
    private func makeTestContext() throws -> (ModelContext, SyncEngine) {
        let schema = Schema([
            Account.self, WalletAddress.self, Position.self,
            PositionToken.self, Asset.self,
            PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        // Use a fresh ModelContext per test — container.mainContext shares thread-local
        // state across tests which causes SIGTRAP when multiple containers exist.
        let context = ModelContext(container)
        let mockStore = MockSecretStore()
        let engine = SyncEngine(modelContext: context, secretStore: mockStore)
        return (context, engine)
    }

    @Test func `sync with no accounts throws`() async throws {
        let (_, engine) = try makeTestContext()
        do {
            _ = try await engine.sync()
            Issue.record("Expected SyncError.noActiveAccounts")
        } catch let error as SyncError {
            #expect(error == .noActiveAccounts)
        }
    }

    @Test func `sync manual only accounts creates snapshots`() async throws {
        let (context, engine) = try makeTestContext()
        let asset = Asset(symbol: "GOLD", name: "Gold Token", category: .other)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 100, usdValue: 5000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 5000, tokens: [token])
        let account = Account(name: "Manual", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        let result = try await engine.sync()

        let snapshots = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots[0].totalValue == 5000)
        #expect(snapshots[0].isPartial == false)
        #expect(result.failedAccounts.isEmpty)
    }

    @Test func `snapshot batch ids link correctly`() async throws {
        let (context, engine) = try makeTestContext()
        let asset = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        context.insert(asset)
        let token = PositionToken(role: .balance, amount: 10, usdValue: 25000, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 25000, tokens: [token])
        let account = Account(name: "Wallet A", kind: .manual, dataSource: .manual, positions: [position])
        context.insert(account)
        try context.save()

        let result = try await engine.sync()

        let portfolioSnaps = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        let accountSnaps = try context.fetch(FetchDescriptor<AccountSnapshot>())
        let assetSnaps = try context.fetch(FetchDescriptor<AssetSnapshot>())

        #expect(portfolioSnaps.count == 1)
        #expect(accountSnaps.count == 1)
        #expect(assetSnaps.count == 1)

        let batchId = portfolioSnaps[0].syncBatchId
        #expect(accountSnaps[0].syncBatchId == batchId)
        #expect(assetSnaps[0].syncBatchId == batchId)
        #expect(accountSnaps[0].accountId == account.id)
        #expect(assetSnaps[0].assetId == asset.id)
        #expect(assetSnaps[0].symbol == "ETH")
        #expect(result.failedAccounts.isEmpty)
    }
}

// MARK: - MockSecretStore

private final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func get(key: String) throws(KeychainError) -> String? {
        store[key]
    }

    func set(key: String, value: String) throws(KeychainError) {
        store[key] = value
    }

    func delete(key: String) throws(KeychainError) {
        store.removeValue(forKey: key)
    }
}
