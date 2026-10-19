@testable import Portu
import Testing

/// The name order Platforms and the All Positions protocol filter share (AGENT-DECIDED 8). The
/// number, case and accent tests order differently under plain `<`, and the accent test also
/// under a literal case-insensitive compare, so a comparator that dropped the localized order
/// fails them.
struct NameOrderTests {
    @Test func `numbers order by value`() {
        #expect(NameOrder.isOrderedBefore("Pool 2", "Pool 10"))
        #expect(!NameOrder.isOrderedBefore("Pool 10", "Pool 2"))
        #expect(NameOrder.lowest(["Pool 10", "Pool 2"]) == "Pool 2")
    }

    /// The first letters differ, so case cannot decide the order under any host collation. Names
    /// that differ only in case would not do: Danish and Maltese collation puts "Aave" before
    /// "aave".
    @Test func `letters order without regard to case`() {
        #expect(NameOrder.isOrderedBefore("balancer", "Curve"))
        #expect(NameOrder.lowest(["Curve", "balancer"]) == "balancer")
    }

    @Test func `an accented letter orders with its base letter`() {
        #expect(NameOrder.isOrderedBefore("étoile", "fox"))
        #expect(NameOrder.lowest(["fox", "étoile"]) == "étoile")
    }

    @Test func `a name is not ordered before itself`() {
        #expect(!NameOrder.isOrderedBefore("Aave", "Aave"))
        #expect(NameOrder.lowest(["Aave", "Aave"]) == "Aave")
    }

    @Test func `no names give no lowest name`() {
        #expect(NameOrder.lowest([String]()) == nil)
    }
}
