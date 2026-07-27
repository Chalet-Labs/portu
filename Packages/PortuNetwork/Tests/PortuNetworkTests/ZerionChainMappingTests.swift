import PortuCore
@testable import PortuNetwork
import Testing

struct ZerionChainMappingTests {
    @Test func `live discovered Portu overlap maps in both directions`() throws {
        let expected: [Chain: String] = [
            .ethereum: "ethereum",
            .polygon: "polygon",
            .arbitrum: "arbitrum",
            .optimism: "optimism",
            .base: "base",
            .bsc: "binance-smart-chain",
            .degen: "degen",
            .gnosis: "xdai",
            .celo: "celo",
            .opBNB: "opbnb",
            .unichain: "unichain",
            .berachain: "berachain",
            .sonic: "sonic",
            .zksync: "zksync-era",
            .polygonZkEVM: "polygon-zkevm",
            .ronin: "ronin",
            .mantle: "mantle",
            .mode: "mode",
            .linea: "linea",
            .blast: "blast",
            .taiko: "taiko",
            .scroll: "scroll",
            .hyperEVM: "hyperevm",
            .zora: "zora",
            .solana: "solana",
            .avalanche: "avalanche",
            .monad: "monad",
            .katana: "katana"
        ]

        #expect(ZerionChainMapping.verified == expected)
        for (chain, id) in expected {
            #expect(try ZerionChainMapping.id(for: chain) == id)
            #expect(try ZerionChainMapping.chain(for: id) == chain)
        }
    }

    @Test(
        arguments: [Chain.bitcoin, .immutableX, .moonbeam, .hyperliquid])
    func `unsupported chains fail without fabricated mappings`(chain: Chain) {
        #expect(ZerionChainMapping.verified[chain] == nil)
        #expect(throws: ZerionError.unsupportedChain(chain.rawValue)) {
            try ZerionChainMapping.id(for: chain)
        }
    }

    @Test func `generic EVM chain filters include only chains supported by positions`() {
        let chunks = ZerionChainMapping.genericEVMChainIDChunks
        let ids = chunks.flatMap(\.self)

        #expect(chunks.map(\.count) == [23])
        #expect(ids == ids.sorted())
        #expect(!ids.contains("solana"))
        #expect(!ids.contains("mode"))
        #expect(!ids.contains("opbnb"))
        #expect(!ids.contains("ronin"))
        #expect(!ids.contains("taiko"))
    }

    @Test func `native and contract implementations round trip`() throws {
        let native = OnchainTokenIdentity.native(on: .ethereum)
        let contract = OnchainTokenIdentity(chain: .base, contractAddress: " 0xAbC ")

        #expect(try ZerionChainMapping.implementation(for: native) == "ethereum")
        #expect(try ZerionChainMapping.implementation(for: contract) == "base:0xabc")
        #expect(try ZerionChainMapping.identity(for: "ethereum") == native)
        #expect(try ZerionChainMapping.identity(for: "base:0xABC") == contract)
    }
}
