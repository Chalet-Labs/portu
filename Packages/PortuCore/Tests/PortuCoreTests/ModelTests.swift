import Foundation
@testable import PortuCore
import SwiftData
import Testing

/// Helper to create an in-memory ModelContainer with all model types
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Account.self,
        WalletAddress.self,
        Position.self,
        PositionToken.self,
        Asset.self,
        PortfolioSnapshot.self,
        AccountSnapshot.self,
        AssetSnapshot.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
struct ModelTests {
    @Test func `create account`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let account = Account(
            name: "My Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "My Wallet")
        #expect(fetched[0].kind == .wallet)
        #expect(fetched[0].dataSource == .zapper)
        #expect(fetched[0].isActive == true)
        #expect(fetched[0].lastSyncError == nil)
    }

    @Test func `account cascade deletes addresses`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", kind: .wallet, dataSource: .zapper)
        let addr = WalletAddress(address: "0xabc123")
        account.addresses.append(addr)
        context.insert(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WalletAddress>()).count == 1)

        context.delete(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WalletAddress>()).isEmpty)
    }

    @Test func `account cascade deletes positions`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", kind: .wallet, dataSource: .zapper)
        let position = Position(positionType: .idle, chain: .ethereum, netUSDValue: 1000)
        account.positions.append(position)
        context.insert(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)

        context.delete(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).isEmpty)
    }

    @Test func `position cascade deletes tokens`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let asset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        context.insert(asset)

        let token = PositionToken(role: .balance, amount: 10, usdValue: 21880, asset: asset)
        let position = Position(positionType: .idle, chain: .ethereum, netUSDValue: 21880, tokens: [token])
        context.insert(position)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PositionToken>()).count == 1)

        context.delete(position)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PositionToken>()).isEmpty)
        // Asset survives — shared reference data
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    @Test func `deleting asset does not cascade delete token`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let asset = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        let token = PositionToken(role: .balance, amount: 10, usdValue: 21880, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 21880, tokens: [token])
        context.insert(position)
        context.insert(asset)
        try context.save()

        context.delete(asset)
        try context.save()

        // Asset is gone
        #expect(try context.fetch(FetchDescriptor<Asset>()).isEmpty)
        // Token survives — nullify, not cascade
        let tokens = try context.fetch(FetchDescriptor<PositionToken>())
        #expect(tokens.count == 1)
    }

    @Test func `full cascade delete chain`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let asset = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major)
        let token = PositionToken(role: .balance, amount: 1, usdValue: 67500, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 67500, tokens: [token])
        let account = Account(name: "Hardware", kind: .wallet, dataSource: .zapper, positions: [position])
        context.insert(account)
        context.insert(asset)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PositionToken>()).count == 1)

        context.delete(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Position>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PositionToken>()).isEmpty)
        // Asset survives
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    @Test func `snapshots use UUID keys not relationships`() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let accountId = UUID()
        let assetId = UUID()
        let batchId = UUID()
        let now = Date.now

        let portfolioSnap = PortfolioSnapshot(
            syncBatchId: batchId, timestamp: now,
            totalValue: 100_000, idleValue: 50000,
            deployedValue: 45000, debtValue: 5000, isPartial: false
        )
        let accountSnap = AccountSnapshot(
            syncBatchId: batchId, timestamp: now,
            accountId: accountId, totalValue: 50000, isFresh: true
        )
        let assetSnap = AssetSnapshot(
            syncBatchId: batchId, timestamp: now,
            accountId: accountId, assetId: assetId,
            symbol: "ETH", category: .major,
            amount: 10, usdValue: 21880
        )

        context.insert(portfolioSnap)
        context.insert(accountSnap)
        context.insert(assetSnap)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetSnapshot>()).count == 1)

        let fetched = try context.fetch(FetchDescriptor<AssetSnapshot>())
        #expect(fetched[0].syncBatchId == batchId)
        #expect(fetched[0].borrowAmount == 0)
    }

    @Test func `account is active by default`() {
        let account = Account(name: "Test", kind: .wallet, dataSource: .zapper)
        #expect(account.isActive == true)
    }

    @Test func `evm address has nil chain`() {
        let addr = WalletAddress(address: "0xabc")
        #expect(addr.chain == nil)
    }

    @Test func `solana address has explicit chain`() {
        let addr = WalletAddress(chain: .solana, address: "SoL123abc")
        #expect(addr.chain == .solana)
    }
}
