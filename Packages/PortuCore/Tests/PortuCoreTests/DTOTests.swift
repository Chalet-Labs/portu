import Testing
import Foundation
@testable import PortuCore

@Suite("DTO Tests")
struct DTOTests {

    @Test func syncContextCreation() {
        let ctx = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [("0xabc", nil), ("SoL123", .solana)],
            exchangeType: nil
        )
        #expect(ctx.kind == .wallet)
        #expect(ctx.addresses.count == 2)
        #expect(ctx.addresses[0].chain == nil) // EVM — all chains
        #expect(ctx.addresses[1].chain == .solana)
    }

    @Test func positionDTOCreation() {
        let token = TokenDTO(
            role: .balance,
            symbol: "ETH",
            name: "Ethereum",
            amount: 10,
            usdValue: 21880,
            chain: .ethereum,
            contractAddress: nil,
            debankId: nil,
            coinGeckoId: "ethereum",
            sourceKey: nil,
            logoURL: nil,
            category: .major,
            isVerified: true
        )
        let pos = PositionDTO(
            positionType: .idle,
            chain: .ethereum,
            protocolId: nil,
            protocolName: nil,
            protocolLogoURL: nil,
            healthFactor: nil,
            tokens: [token]
        )
        #expect(pos.tokens.count == 1)
        #expect(pos.tokens[0].symbol == "ETH")
        #expect(pos.positionType == .idle)
    }

    @Test func tokenDTOAmountsArePositive() {
        let borrow = TokenDTO(
            role: .borrow,
            symbol: "USDC",
            name: "USD Coin",
            amount: 5000,
            usdValue: 5000,
            chain: .ethereum,
            contractAddress: "0xa0b8...",
            debankId: nil,
            coinGeckoId: "usd-coin",
            sourceKey: nil,
            logoURL: nil,
            category: .stablecoin,
            isVerified: true
        )
        #expect(borrow.amount > 0)
        #expect(borrow.usdValue > 0)
        #expect(borrow.role == .borrow)
    }

    @Test func priceUpdateCreation() {
        let update = PriceUpdate(
            prices: ["ethereum": 2188, "bitcoin": 67500],
            changes24h: ["ethereum": Decimal(string: "0.032")!, "bitcoin": Decimal(string: "-0.015")!]
        )
        #expect(update.prices.count == 2)
        #expect(update.changes24h["ethereum"]! > 0)
        #expect(update.changes24h["bitcoin"]! < 0)
    }
}
