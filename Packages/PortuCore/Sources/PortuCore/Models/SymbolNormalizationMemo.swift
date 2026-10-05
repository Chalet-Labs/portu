import Foundation
import Synchronization

/// Remembers how raw symbols normalize. Normalization is pure, so entries never go stale, and the
/// table is bounded: once a new symbol would exceed `capacity` the table restarts with just that
/// symbol, which keeps a stream of unique symbols from pinning the table full of dead entries.
final class SymbolNormalizationMemo: Sendable {
    private let capacity: Int
    private let normalize: @Sendable (String) -> String
    private let table = Mutex<[String: String]>([:])

    init(
        capacity: Int = 16384,
        normalize: @escaping @Sendable (String) -> String = PortfolioCategoryDefaults.normalizeSymbol) {
        self.capacity = capacity
        self.normalize = normalize
    }

    func normalized(_ symbol: String) -> String {
        if let hit = table.withLock({ $0[symbol] }) {
            return hit
        }
        // Computed outside the lock so concurrent first misses never serialize on the work itself.
        // Two threads may both compute the same symbol; the later insert just overwrites an
        // identical entry, which is why an existing key never counts as overflow.
        let value = normalize(symbol)
        table.withLock { table in
            if table[symbol] == nil, table.count >= capacity {
                table.removeAll(keepingCapacity: true)
            }
            table[symbol] = value
        }
        return value
    }

    /// The remembered normalization, without computing it. Lets tests see what the memo holds.
    func cachedNormalization(for symbol: String) -> String? {
        table.withLock { $0[symbol] }
    }
}
