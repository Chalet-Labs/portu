import Foundation
import PortuCore
import Testing

struct PortfolioCategoryResolverTests {
    @Test func `default categories exclude sui and include app wide buckets`() {
        let names = PortfolioCategoryDefaults.categorySnapshots.map(\.name)

        #expect(names == [
            "BTC",
            "ETH",
            "SOL",
            "DeFi",
            "Meme",
            "Privacy",
            "Fiat",
            "Stablecoins",
            "Other Tokens"
        ])
        #expect(names.contains("SUI") == false)
    }

    @Test func `default symbol rules map btc eth and sol families`() {
        let resolver = PortfolioCategoryResolver.defaults

        #expect(resolver.resolve(symbol: "BTC", legacyCategory: .other).name == "BTC")
        #expect(resolver.resolve(symbol: "cb-btc", legacyCategory: .other).name == "BTC")
        #expect(resolver.resolve(symbol: "WETH", legacyCategory: .defi).name == "ETH")
        #expect(resolver.resolve(symbol: "st eth", legacyCategory: .defi).name == "ETH")
        #expect(resolver.resolve(symbol: "jito_sol", legacyCategory: .other).name == "SOL")
        #expect(resolver.resolve(symbol: "SUI", legacyCategory: .major).name == "Other Tokens")
    }

    @Test func `default symbol rules map common stablecoins even when provider category is unknown`() {
        let resolver = PortfolioCategoryResolver.defaults

        #expect(resolver.resolve(symbol: "USDC", legacyCategory: .other).name == "Stablecoins")
        #expect(resolver.resolve(symbol: "usdc.e", legacyCategory: .other).name == "Stablecoins")
        #expect(resolver.resolve(symbol: "USDT", legacyCategory: .other).name == "Stablecoins")
        #expect(resolver.resolve(symbol: "DAI", legacyCategory: .other).name == "Stablecoins")
        #expect(resolver.resolve(symbol: "PYUSD", legacyCategory: .other).name == "Stablecoins")
    }

    @Test func `global symbol rules override legacy import category`() throws {
        let category = try PortfolioCategorySnapshot(
            id: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
            name: "Majors",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let resolver = try PortfolioCategoryResolver(
            categories: [category, PortfolioCategoryDefaults.fallbackCategory],
            rules: [
                CategorySymbolRuleSnapshot(
                    id: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
                    symbol: "ETH",
                    categoryId: category.id)
            ])

        let resolved = resolver.resolve(symbol: "ETH", legacyCategory: .defi)

        #expect(resolved.name == "Majors")
    }

    @Test func `legacy categories map to configurable fallback categories`() {
        let resolver = PortfolioCategoryResolver.defaults

        #expect(resolver.resolve(symbol: "UNI", legacyCategory: .defi).name == "DeFi")
        #expect(resolver.resolve(symbol: "PEPE", legacyCategory: .meme).name == "Meme")
        #expect(resolver.resolve(symbol: "XMR", legacyCategory: .privacy).name == "Privacy")
        #expect(resolver.resolve(symbol: "CHF", legacyCategory: .fiat).name == "Fiat")
        #expect(resolver.resolve(symbol: "USDC", legacyCategory: .stablecoin).name == "Stablecoins")
        #expect(resolver.resolve(symbol: "OP", legacyCategory: .governance).name == "Other Tokens")
        #expect(resolver.resolve(symbol: "UNKNOWN", legacyCategory: .major).name == "Other Tokens")
    }

    @Test func `stablecoin semantic role is resolved from user categories`() {
        let resolver = PortfolioCategoryResolver.defaults

        #expect(resolver.isStablecoin(symbol: "DAI", legacyCategory: .stablecoin))
        #expect(resolver.isStablecoin(symbol: "ETH", legacyCategory: .stablecoin) == false)
    }

    @Test func `resolver synthesizes fallback when fallback category is missing`() throws {
        let category = try PortfolioCategorySnapshot(
            id: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
            name: "Custom",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let resolver = PortfolioCategoryResolver(categories: [category], rules: [])

        let resolved = resolver.resolve(symbol: "UNKNOWN", legacyCategory: .other)

        #expect(resolved.name == "Other Tokens")
        #expect(resolved.semanticRole == .fallback)
    }

    @Test func `symbol normalization trims uppercases and removes separators`() {
        #expect(PortfolioCategoryDefaults.normalizeSymbol("  cb-btc ") == "CBBTC")
        #expect(PortfolioCategoryDefaults.normalizeSymbol("st eth") == "STETH")
        #expect(PortfolioCategoryDefaults.normalizeSymbol("jito_sol") == "JITOSOL")
    }
}
