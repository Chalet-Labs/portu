import Foundation
import Testing
@testable import PortuCore

@Suite("Transport Type Tests")
struct TransportTypeTests {
    @Test func syncContextCapturesAccountScope() {
        let context = SyncContext(
            accountId: UUID(),
            kind: .exchange,
            addresses: [],
            exchangeType: .kraken
        )

        #expect(context.exchangeType == .kraken)
    }

    @Test func positionDTOStoresTokenMetadata() throws {
        let token = TokenDTO(
            role: .supply,
            symbol: "ETH",
            name: "Ethereum",
            amount: 2,
            usdValue: 4_000,
            chain: .ethereum,
            contractAddress: "0xabc",
            debankId: nil,
            coinGeckoId: "ethereum",
            sourceKey: "zapper:ethereum",
            logoURL: "https://example.com/eth.png",
            category: .major,
            isVerified: true
        )
        let position = PositionDTO(
            positionType: .lending,
            chain: .ethereum,
            protocolId: "aave-v3",
            protocolName: "Aave V3",
            protocolLogoURL: "https://example.com/aave.png",
            healthFactor: 1.5,
            tokens: [token]
        )

        let firstToken = try #require(position.tokens.first)
        #expect(firstToken.coinGeckoId == "ethereum")
        #expect(position.protocolName == "Aave V3")
    }
}
