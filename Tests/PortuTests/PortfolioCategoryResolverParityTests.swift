import Foundation
import PortuCore
import Testing

/// `resolve` runs for every row of every view on each render, so any spelling of a symbol has to
/// keep landing in the same category however the lookup is sped up.
struct PortfolioCategoryResolverParityTests {
    struct Spelling: Sendable, CustomTestStringConvertible {
        let raw: String
        let legacyCategory: AssetCategory
        let expectedCategory: String

        var testDescription: String {
            "\(raw.debugDescription) / \(legacyCategory) -> \(expectedCategory)"
        }
    }

    /// Written by hand against `PortfolioCategoryResolver.defaults`: rule hits win over the legacy
    /// category, everything else falls back to the legacy category's bucket.
    static let spellings = [
        Spelling(raw: "BTC", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "btc", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "  btc  ", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "\tbtc\n", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "\n WBTC \r\n", legacyCategory: .defi, expectedCategory: "BTC"),
        Spelling(raw: "cb-btc", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "cb_btc", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "cb.btc", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "cb btc", legacyCategory: .other, expectedCategory: "BTC"),
        Spelling(raw: "C-b_B.t c", legacyCategory: .meme, expectedCategory: "BTC"),
        Spelling(raw: "usdc.e", legacyCategory: .other, expectedCategory: "Stablecoins"),
        Spelling(raw: "USDC.E", legacyCategory: .meme, expectedCategory: "Stablecoins"),
        Spelling(raw: "usdce", legacyCategory: .other, expectedCategory: "Stablecoins"),
        Spelling(raw: "usdt", legacyCategory: .meme, expectedCategory: "Stablecoins"),
        Spelling(raw: "st eth", legacyCategory: .defi, expectedCategory: "ETH"),
        Spelling(raw: "ST-ETH", legacyCategory: .defi, expectedCategory: "ETH"),
        Spelling(raw: "wst_eth", legacyCategory: .other, expectedCategory: "ETH"),
        Spelling(raw: "jito_sol", legacyCategory: .other, expectedCategory: "SOL"),
        Spelling(raw: "SUI", legacyCategory: .major, expectedCategory: "Other Tokens"),
        Spelling(raw: "UNI", legacyCategory: .defi, expectedCategory: "DeFi"),
        Spelling(raw: "pepe", legacyCategory: .meme, expectedCategory: "Meme"),
        Spelling(raw: "xmr", legacyCategory: .privacy, expectedCategory: "Privacy"),
        Spelling(raw: "chf", legacyCategory: .fiat, expectedCategory: "Fiat"),
        Spelling(raw: "op", legacyCategory: .governance, expectedCategory: "Other Tokens"),
        Spelling(raw: "btcx", legacyCategory: .other, expectedCategory: "Other Tokens"),
        Spelling(raw: "xbtc", legacyCategory: .meme, expectedCategory: "Meme"),
        Spelling(raw: "???", legacyCategory: .other, expectedCategory: "Other Tokens"),
        Spelling(raw: "", legacyCategory: .stablecoin, expectedCategory: "Stablecoins"),
        Spelling(raw: "   ", legacyCategory: .privacy, expectedCategory: "Privacy"),
        Spelling(raw: "-_.", legacyCategory: .defi, expectedCategory: "DeFi"),
        Spelling(raw: "\u{00A0}eth\u{00A0}", legacyCategory: .other, expectedCategory: "ETH")
    ]

    @Test(arguments: spellings)
    func `a spelling resolves to the written category every time`(_ spelling: Spelling) {
        let resolver = PortfolioCategoryResolver.defaults

        for _ in 0 ..< 3 {
            let resolved = resolver.resolve(symbol: spelling.raw, legacyCategory: spelling.legacyCategory)
            #expect(resolved.name == spelling.expectedCategory)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `concurrent resolution agrees with the written categories`() {
        let resolver = PortfolioCategoryResolver.defaults
        let failures = ConcurrentFailureLog()

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for round in 0 ..< 100 {
                for offset in Self.spellings.indices {
                    let spelling = Self.spellings[(worker + offset) % Self.spellings.count]
                    let resolved = resolver.resolve(symbol: spelling.raw, legacyCategory: spelling.legacyCategory)
                    failures.check(
                        resolved.name == spelling.expectedCategory,
                        "worker \(worker) round \(round): \(spelling.testDescription) gave \(resolved.name)")
                }
            }
        }

        #expect(failures.all == [])
    }

    /// Guards a shared lookup cache against ever remembering a category: the same spelling must
    /// resolve differently under resolvers whose rules differ.
    @Test(.timeLimit(.minutes(1)))
    func `resolvers with different rules never share a result for the same spelling`() throws {
        let alpha = try Self.category("Alpha", id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", sortOrder: 0)
        let beta = try Self.category("Beta", id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", sortOrder: 1)
        let categories = [alpha, beta, PortfolioCategoryDefaults.fallbackCategory]
        let resolvers = try [
            PortfolioCategoryResolver(
                categories: categories,
                rules: [Self.rule("ETH", category: alpha, id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")]),
            PortfolioCategoryResolver(
                categories: categories,
                rules: [Self.rule("ETH", category: beta, id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")]),
            PortfolioCategoryResolver(categories: categories, rules: [])
        ]
        let expectedNames = ["Alpha", "Beta", "Other Tokens"]
        let spellings = ["ETH", " eth ", "e-th", "E_T.H", "e t h"]
        let failures = ConcurrentFailureLog()

        // Interleave on one thread, then again across threads.
        for spelling in spellings {
            for (resolver, expected) in zip(resolvers, expectedNames) {
                let resolved = resolver.resolve(symbol: spelling, legacyCategory: .defi)
                failures.check(resolved.name == expected, "\(spelling.debugDescription) gave \(resolved.name), expected \(expected)")
            }
        }
        DispatchQueue.concurrentPerform(iterations: 9) { worker in
            for round in 0 ..< 100 {
                let index = (worker + round) % resolvers.count
                let spelling = spellings[(worker * 7 + round) % spellings.count]
                let resolved = resolvers[index].resolve(symbol: spelling, legacyCategory: .defi)
                failures.check(
                    resolved.name == expectedNames[index],
                    "worker \(worker) round \(round): \(spelling.debugDescription) gave \(resolved.name), expected \(expectedNames[index])")
            }
        }

        #expect(failures.all == [])
    }

    // MARK: - Helpers

    private static func category(_ name: String, id: String, sortOrder: Int) throws -> PortfolioCategorySnapshot {
        try PortfolioCategorySnapshot(
            id: #require(UUID(uuidString: id)),
            name: name,
            sortOrder: sortOrder,
            semanticRole: .normal,
            isSystemRequired: false)
    }

    private static func rule(_ symbol: String, category: PortfolioCategorySnapshot, id: String) throws -> CategorySymbolRuleSnapshot {
        try CategorySymbolRuleSnapshot(
            id: #require(UUID(uuidString: id)),
            symbol: symbol,
            categoryId: category.id)
    }
}
