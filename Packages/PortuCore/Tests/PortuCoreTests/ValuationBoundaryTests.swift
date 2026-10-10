import Foundation
import PortuCore
import SwiftData
import Testing

@MainActor
struct ValuationBoundaryTests {
    private typealias Fixture = ValuationFixtures

    @Test func `active accounts input keeps position context and drops inactive accounts and asset less tokens`() throws {
        let context = try makeContext()
        let active = Account(name: "Wallet", kind: .wallet, dataSource: .zapper)
        let inactive = Account(name: "Old", kind: .wallet, dataSource: .zapper, isActive: false)
        let asset = Asset(symbol: "ETH", name: "Ether", coinGeckoId: "ethereum", upsertChain: .ethereum, upsertContract: "0xabc")
        let position = Position(positionType: .lending, chain: .base, protocolId: "aave", account: active, syncedAt: Fixture.noon(-1))
        let stale = Position(positionType: .idle, account: inactive)
        let token = PositionToken(role: .supply, amount: 2, usdValue: 10, asset: asset, position: position)
        let orphan = PositionToken(role: .supply, amount: 1, usdValue: 5, position: position)
        let inactiveToken = PositionToken(role: .balance, amount: 1, usdValue: 7, asset: asset, position: stale)
        for model in [active, inactive] as [any PersistentModel] + [asset, position, stale, token, orphan, inactiveToken] {
            context.insert(model)
        }

        let inputs = ValuationInput.activeAccounts([token, orphan, inactiveToken])
        let everything = ValuationInput.allAccounts([token, orphan, inactiveToken])

        let input = try #require(inputs.first)
        #expect(inputs.count == 1)
        #expect(everything.count == 2)
        #expect(input.position == PositionContext(
            positionId: position.id,
            positionType: .lending,
            accountId: active.id,
            chain: .base,
            protocolId: "aave"))
        #expect(input.tokenId == token.id)
        #expect(input.token.assetId == asset.id)
        #expect(input.token.coinGeckoId == "ethereum")
        #expect(input.token.syncedAt == Fixture.noon(-1))
        #expect(input.token.onchainIdentity == OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xabc"))
    }

    @Test func `close rows project price id day currency and price from stored points`() throws {
        let context = try makeContext()
        let point = HistoricalPricePoint(coinGeckoId: "ethereum", day: Fixture.noon(-1), currency: .eur, price: 3000)
        context.insert(point)

        let row = HistoricalCloseRow(point)

        #expect(row == HistoricalCloseRow(priceID: "ethereum", day: Fixture.day(-1), currency: .eur, price: 3000))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Account.self, Position.self, PositionToken.self, Asset.self, HistoricalPricePoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}
