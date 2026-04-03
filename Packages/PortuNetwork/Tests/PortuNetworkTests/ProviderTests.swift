import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

struct ProviderTests {
    @Test func `mock provider returns balances`() async throws {
        let provider = MockProvider()
        let ethToken = TokenDTO(
            role: .balance, symbol: "ETH", name: "Ethereum",
            amount: 10, usdValue: 21880, chain: .ethereum,
            contractAddress: nil, debankId: nil, coinGeckoId: "ethereum",
            sourceKey: nil, logoURL: nil, category: .major, isVerified: true)
        let position = PositionDTO(
            positionType: .idle, chain: .ethereum,
            protocolId: nil, protocolName: nil, protocolLogoURL: nil,
            healthFactor: nil, tokens: [ethToken])
        await provider.configure(balances: [position])

        let ctx = SyncContext(accountId: UUID(), kind: .wallet, addresses: [("0xabc", nil)], exchangeType: nil)
        let results = try await provider.fetchBalances(context: ctx)

        #expect(results.count == 1)
        #expect(results[0].tokens[0].symbol == "ETH")
        #expect(await provider.fetchBalancesCalled)
    }

    @Test func `provider capabilities default`() {
        let caps = ProviderCapabilities()
        #expect(caps.supportsTokenBalances)
        #expect(!caps.supportsDeFiPositions)
        #expect(!caps.supportsHealthFactors)
    }

    @Test func `zapper capabilities`() {
        let provider = ZapperProvider(apiKey: "test-key")
        let caps = provider.capabilities
        #expect(caps.supportsTokenBalances)
        #expect(caps.supportsDeFiPositions)
    }
}
