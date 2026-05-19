import Foundation
@testable import Portu
import PortuCore
import Testing

struct TokenIdentityMappingFeatureTests {
    @Test func `normalized provider id trims and lowercases`() {
        #expect(TokenIdentityMappingFeature.normalizedProviderID("  Bitcoin  ") == "bitcoin")
        #expect(TokenIdentityMappingFeature.normalizedProviderID("eThEReuM") == "ethereum")
    }

    @Test func `normalized provider id returns nil for empty or whitespace input`() {
        #expect(TokenIdentityMappingFeature.normalizedProviderID(nil) == nil)
        #expect(TokenIdentityMappingFeature.normalizedProviderID("") == nil)
        #expect(TokenIdentityMappingFeature.normalizedProviderID("   ") == nil)
    }

    @Test func `normalized historical price id canonicalizes legacy zapper prefix to asset prefix`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        #expect(
            TokenIdentityMappingFeature.normalizedHistoricalPriceID("zapper:base:0xLocal")
                == identity.historicalPriceID)
        #expect(identity.historicalPriceID.hasPrefix("asset:"))
    }

    @Test func `normalized historical price id leaves plain coin gecko ids alone aside from normalization`() {
        #expect(TokenIdentityMappingFeature.normalizedHistoricalPriceID(" BITCOIN ") == "bitcoin")
        #expect(TokenIdentityMappingFeature.normalizedHistoricalPriceID(nil) == nil)
    }

    @Test func `mappings by identity dedupes by canonical identity preferring entries with coin gecko id`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let unresolved = try TokenIdentityMappingSnapshot(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            identity: identity)
        let resolved = try TokenIdentityMappingSnapshot(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            identity: identity,
            coinGeckoId: "wrapped-local")

        let map = TokenIdentityMappingFeature.mappingsByIdentity([unresolved, resolved])

        #expect(map[identity]?.coinGeckoId == "wrapped-local")
    }

    @Test func `native coin gecko id resolves zero address on ethereum like chains to ethereum`() {
        let zeroAddress = "0x0000000000000000000000000000000000000000"
        for chain in [Chain.ethereum, .arbitrum, .optimism, .base, .scroll, .zora] {
            let identity = OnchainTokenIdentity(chain: chain, contractAddress: zeroAddress)
            #expect(TokenIdentityMappingFeature.nativeCoinGeckoID(for: identity) == "ethereum")
        }
    }

    @Test func `native coin gecko id returns nil for non native contract address`() {
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xabc")
        #expect(TokenIdentityMappingFeature.nativeCoinGeckoID(for: identity) == nil)
    }

    @Test func `known contract coin gecko id resolves usdc on supported chains case insensitively`() {
        let identity = OnchainTokenIdentity(
            chain: .arbitrum,
            contractAddress: "0xAF88D065E77C8CC2239327C5EDB3A432268E5831")
        #expect(TokenIdentityMappingFeature.knownContractCoinGeckoID(for: identity) == "usd-coin")
    }

    @Test func `known contract coin gecko id returns nil for unknown contract`() {
        let identity = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xdeadbeef")
        #expect(TokenIdentityMappingFeature.knownContractCoinGeckoID(for: identity) == nil)
    }

    @Test func `non zapper price id rejects asset prefixed historical price ids`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        #expect(TokenIdentityMappingFeature.nonZapperPriceID(identity.historicalPriceID) == nil)
        #expect(TokenIdentityMappingFeature.nonZapperPriceID("bitcoin") == "bitcoin")
        #expect(TokenIdentityMappingFeature.nonZapperPriceID(nil) == nil)
    }

    @Test func `price id prefers native coin gecko id when identity is zero address on eth like chain`() {
        let identity = OnchainTokenIdentity(
            chain: .base,
            contractAddress: "0x0000000000000000000000000000000000000000")

        let priceID = TokenIdentityMappingFeature.priceID(
            coinGeckoId: "ignored-override",
            onchainIdentity: identity)

        #expect(priceID == "ethereum")
    }

    @Test func `price id falls back to historical price id when identity is not native`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")

        let priceID = TokenIdentityMappingFeature.priceID(
            coinGeckoId: nil,
            onchainIdentity: identity)

        #expect(priceID == identity.historicalPriceID)
    }

    @Test func `price id falls back to coin gecko id when no onchain identity is given`() {
        let priceID = TokenIdentityMappingFeature.priceID(coinGeckoId: " Bitcoin ", onchainIdentity: nil)
        #expect(priceID == "bitcoin")
    }
}
