import Foundation

/// Names in localized standard order, ties under it broken by `<` so the order is total.
enum NameOrder {
    static func isOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let order = lhs.localizedStandardCompare(rhs)
        return order == .orderedSame ? lhs < rhs : order == .orderedAscending
    }

    /// The first name in this order, or `nil` for none: how Platforms names a platform and All
    /// Positions a protocol option (AGENT-DECIDED 8).
    static func lowest(_ names: some Sequence<String>) -> String? {
        names.min(by: isOrderedBefore)
    }
}
