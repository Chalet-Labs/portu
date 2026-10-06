import Foundation
@testable import PortuCore
import SwiftData
import Testing

@MainActor
struct TokenEntrySyncTimeTests {
    private let syncedAt = Date(timeIntervalSince1970: 1_759_700_000)

    @Test func `entry built from a position token carries the position's sync time`() throws {
        let container = try makeTestContainer()
        let token = insertToken(into: container.mainContext, syncedAt: syncedAt)
        let asset = try #require(token.asset)

        let entry = TokenEntry(
            token,
            asset: asset,
            portfolioCategory: PortfolioCategoryResolver.defaults.resolve(
                symbol: asset.symbol,
                legacyCategory: asset.category),
            coinGeckoId: asset.coinGeckoId)

        #expect(entry.syncedAt == syncedAt)
        #expect(entry.assetId == asset.id)
        #expect(entry.coinGeckoId == "ethereum")
        #expect(entry.onchainIdentity == OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xabc"))
        #expect(entry.role == .balance)
        #expect(entry.amount == 2)
        #expect(entry.usdValue == 5000)
        #expect(entry.logoURL == "https://example.com/eth.png")
    }

    @Test func `active token entries carry their position's sync time`() throws {
        let container = try makeTestContainer()
        let token = insertToken(into: container.mainContext, syncedAt: syncedAt)

        let entries = TokenEntry.fromActiveTokens([token])

        #expect(entries.map(\.syncedAt) == [syncedAt])
    }

    @Test func `entry built from a token without a position has no sync time`() throws {
        let container = try makeTestContainer()
        let asset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        let token = PositionToken(role: .balance, amount: 1, usdValue: 2500, asset: asset)
        container.mainContext.insert(token)

        let entry = TokenEntry(
            token,
            asset: asset,
            portfolioCategory: PortfolioCategoryDefaults.fallbackCategory,
            coinGeckoId: asset.coinGeckoId)

        #expect(entry.syncedAt == nil)
    }

    @Test func `entry built without a sync time has none`() {
        let entry = TokenEntry(
            assetId: UUID(),
            symbol: "BTC",
            name: "Bitcoin",
            category: .major,
            coinGeckoId: "bitcoin",
            role: .balance,
            amount: 1,
            usdValue: 60000)

        #expect(entry.syncedAt == nil)
    }

    private func insertToken(into context: ModelContext, syncedAt: Date) -> PositionToken {
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        let position = Position(positionType: .idle, chain: .ethereum, netUSDValue: 5000, syncedAt: syncedAt)
        let asset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            upsertChain: .ethereum,
            upsertContract: "0xABC",
            logoURL: "https://example.com/eth.png",
            category: .major)
        let token = PositionToken(role: .balance, amount: 2, usdValue: 5000, asset: asset)
        position.tokens.append(token)
        account.positions.append(position)
        context.insert(account)
        return token
    }
}
