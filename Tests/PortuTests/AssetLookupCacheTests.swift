@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct AssetLookupCacheTests {
    @Test func `cache trims lookup keys and ignores empty contracts`() {
        let asset = Asset(
            symbol: "ETH", name: "Ethereum",
            coinGeckoId: " ethereum ",
            upsertChain: .ethereum,
            upsertContract: " 0xAbC ",
            sourceKey: " source:key ")
        let whitespaceContract = Asset(
            symbol: "BAD", name: "Bad",
            upsertChain: .ethereum,
            upsertContract: "   ")
        let cache = AssetLookupCache(assets: [asset, whitespaceContract])

        #expect(cache.asset(coinGeckoId: "ethereum") === asset)
        #expect(cache.asset(chain: .ethereum, contract: "0xabc") === asset)
        #expect(cache.asset(sourceKey: "source:key") === asset)
        #expect(cache.asset(chain: .ethereum, contract: "   ") == nil)
    }

    @Test func `upsert ignores whitespace only chain contract identities`() throws {
        let context = try makeAssetContext()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in fatalError("unused") }))
        let whitespaceAsset = Asset(
            symbol: "BAD", name: "Bad",
            upsertChain: .ethereum,
            upsertContract: "   ")
        context.insert(whitespaceAsset)
        try context.save()

        let result = try engine.upsertAsset(from: makeTokenDTO(contractAddress: " \n "))

        #expect(result !== whitespaceAsset)
        #expect(result.upsertContract == nil)
    }

    private func makeAssetContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([Asset.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func makeTokenDTO(contractAddress: String) -> TokenDTO {
        TokenDTO(
            role: .balance,
            symbol: "NEW",
            name: "New",
            amount: 1,
            usdValue: 1,
            chain: .ethereum,
            contractAddress: contractAddress,
            debankId: nil,
            coinGeckoId: nil,
            sourceKey: nil,
            logoURL: nil,
            category: .other,
            isVerified: false)
    }
}
