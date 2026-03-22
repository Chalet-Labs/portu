import Foundation
import Testing
import SwiftData
@testable import PortuCore

@MainActor
@Suite("SwiftData Model Tests")
struct ModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            PortfolioSnapshot.self,
            AccountSnapshot.self,
            AssetSnapshot.self,
            configurations: config
        )
        context = container.mainContext
    }

    @Test func accountStoresAddressesAndSyncMetadata() throws {
        let account = Account(
            name: "Main wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        account.addresses = [WalletAddress(address: "0xabc", chain: nil)]

        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Main wallet")
        #expect(fetched.first?.isActive == true)
        #expect(fetched.first?.addresses.count == 1)
        #expect(fetched.first?.addresses.first?.address == "0xabc")
        #expect(fetched.first?.lastSyncError == nil)
    }

    @Test func positionNetValueUsesSignedTokenRoles() throws {
        let asset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")
        let position = Position(positionType: .lending, netUSDValue: 1000)
        position.tokens = [
            PositionToken(role: .supply, amount: 2, usdValue: 4000, asset: asset),
            PositionToken(role: .borrow, amount: 1, usdValue: 3000, asset: asset),
        ]

        context.insert(asset)
        context.insert(position)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Position>())
        let fetchedPosition = try #require(fetched.first)

        #expect(fetched.count == 1)
        #expect(fetchedPosition.netUSDValue == 1000)
        #expect(fetchedPosition.tokens.count == 2)
        #expect(Set(fetchedPosition.tokens.map(\.role)) == Set([.supply, .borrow]))
    }

    @Test func cascadeDeleteAccountRemovesAddressesAndPositions() throws {
        let account = Account(
            name: "Tracked wallet",
            kind: .wallet,
            dataSource: .manual
        )
        account.addresses = [WalletAddress(address: "0xdef", chain: .ethereum)]

        let asset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")
        let position = Position(positionType: .idle, netUSDValue: 1500)
        position.tokens = [
            PositionToken(role: .supply, amount: 1, usdValue: 1500, asset: asset)
        ]
        account.positions = [position]

        context.insert(asset)
        context.insert(account)
        try context.save()

        context.delete(account)
        try context.save()

        let addresses = try context.fetch(FetchDescriptor<WalletAddress>())
        let positions = try context.fetch(FetchDescriptor<Position>())
        let tokens = try context.fetch(FetchDescriptor<PositionToken>())
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let assets = try context.fetch(FetchDescriptor<Asset>())

        #expect(accounts.isEmpty)
        #expect(addresses.isEmpty)
        #expect(positions.isEmpty)
        #expect(tokens.isEmpty)
        #expect(assets.count == 1)
    }

    @Test func snapshotModelsPersistBatchValues() throws {
        let batchID = UUID()
        let accountID = UUID()
        let assetID = UUID()

        context.insert(
            PortfolioSnapshot(
                syncBatchId: batchID,
                timestamp: .now,
                totalValue: 10_000,
                idleValue: 2_000,
                deployedValue: 7_000,
                debtValue: 1_000,
                isPartial: false
            )
        )
        context.insert(
            AccountSnapshot(
                syncBatchId: batchID,
                timestamp: .now,
                accountId: accountID,
                totalValue: 6_000,
                isFresh: true
            )
        )
        context.insert(
            AssetSnapshot(
                syncBatchId: batchID,
                timestamp: .now,
                accountId: accountID,
                assetId: assetID,
                symbol: "ETH",
                category: .major,
                amount: 2,
                usdValue: 4_000,
                borrowAmount: 0,
                borrowUsdValue: 0
            )
        )

        try context.save()

        let portfolioSnapshots = try context.fetch(FetchDescriptor<PortfolioSnapshot>())
        let accountSnapshots = try context.fetch(FetchDescriptor<AccountSnapshot>())
        let assetSnapshots = try context.fetch(FetchDescriptor<AssetSnapshot>())

        #expect(portfolioSnapshots.count == 1)
        #expect(accountSnapshots.count == 1)
        #expect(assetSnapshots.count == 1)
        #expect(portfolioSnapshots.first?.debtValue == 1_000)
        #expect(accountSnapshots.first?.isFresh == true)
        #expect(assetSnapshots.first?.category == .major)
    }
}
