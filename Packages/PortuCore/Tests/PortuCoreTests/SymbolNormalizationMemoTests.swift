import Foundation
@testable import PortuCore
import Synchronization
import Testing

struct SymbolNormalizationMemoTests {
    /// Wraps the real normalization with a call counter so tests can see when it actually runs.
    private final class CountingNormalizer: Sendable {
        private let calls = Mutex(0)

        var count: Int {
            calls.withLock { $0 }
        }

        var normalize: @Sendable (String) -> String {
            { [self] symbol in
                calls.withLock { $0 += 1 }
                return PortfolioCategoryDefaults.normalizeSymbol(symbol)
            }
        }
    }

    @Test func `a repeated symbol is normalized once`() {
        let counter = CountingNormalizer()
        let memo = SymbolNormalizationMemo(capacity: 100, normalize: counter.normalize)

        let results = (0 ..< 5).map { _ in memo.normalized("  cb-btc ") }

        #expect(results == Array(repeating: "CBBTC", count: 5))
        #expect(counter.count == 1)
    }

    @Test func `different spellings are normalized separately`() {
        let counter = CountingNormalizer()
        let memo = SymbolNormalizationMemo(capacity: 100, normalize: counter.normalize)

        #expect(memo.normalized("cb-btc") == "CBBTC")
        #expect(memo.normalized("cb_btc") == "CBBTC")
        #expect(memo.normalized("cb-btc") == "CBBTC")
        #expect(counter.count == 2)
    }

    @Test func `overflow clears the table and keeps returning correct values`() {
        let counter = CountingNormalizer()
        let memo = SymbolNormalizationMemo(capacity: 3, normalize: counter.normalize)

        for symbol in ["a", "b", "c"] {
            #expect(memo.normalized(symbol) == symbol.uppercased())
        }
        #expect(counter.count == 3)

        // The fourth distinct symbol no longer fits: the table restarts with just that one.
        #expect(memo.normalized("d") == "D")
        #expect(memo.cachedNormalization(for: "a") == nil)
        #expect(memo.cachedNormalization(for: "d") == "D")

        // An evicted symbol is simply computed again.
        #expect(memo.normalized("a") == "A")
        #expect(counter.count == 5)
    }

    @Test func `looking up a remembered symbol at capacity evicts nothing`() {
        let memo = SymbolNormalizationMemo(capacity: 2)
        _ = memo.normalized("a")
        _ = memo.normalized("b")

        _ = memo.normalized("a")

        #expect(memo.cachedNormalization(for: "a") == "A")
        #expect(memo.cachedNormalization(for: "b") == "B")
    }

    /// Concurrent first misses may each compute a value, so this checks results only, never call counts.
    @Test(.timeLimit(.minutes(1)))
    func `concurrent lookups agree with the plain normalization`() {
        let memo = SymbolNormalizationMemo(capacity: 8)
        let symbols = ["btc", " ETH ", "cb-btc", "usdc.e", "st eth", "jito_sol", "\tSUI\n", "pepe", "xmr", "dai", "uni", "op"]
        let mismatches = Mutex<[String]>([])

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for round in 0 ..< 200 {
                let symbol = symbols[(worker + round) % symbols.count]
                let expected = PortfolioCategoryDefaults.normalizeSymbol(symbol)
                let actual = memo.normalized(symbol)
                if actual != expected {
                    mismatches.withLock { $0.append("\(symbol.debugDescription): \(actual) != \(expected)") }
                }
            }
        }

        #expect(mismatches.withLock { $0 } == [])
    }

    /// Without this the counting specs above could pass on an instance the resolver never touches.
    @Test func `resolving a symbol records it in the memo shared by every resolver`() {
        let raw = "  memo-wiring-\(UUID().uuidString) "
        #expect(PortfolioCategoryResolver.normalizationMemo.cachedNormalization(for: raw) == nil)

        _ = PortfolioCategoryResolver.defaults.resolve(symbol: raw, legacyCategory: .other)

        #expect(
            PortfolioCategoryResolver.normalizationMemo.cachedNormalization(for: raw)
                == PortfolioCategoryDefaults.normalizeSymbol(raw))
    }
}
