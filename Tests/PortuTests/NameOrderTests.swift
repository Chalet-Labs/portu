@testable import Portu
import Testing

/// The name order Platforms and the All Positions protocol filter share (AGENT-DECIDED 8). The
/// number and case tests order differently under plain `<`, so a comparator that dropped the
/// localized order fails them.
struct NameOrderTests {
    @Test func `numbers order by value`() {
        #expect(NameOrder.isOrderedBefore("Pool 2", "Pool 10"))
        #expect(!NameOrder.isOrderedBefore("Pool 10", "Pool 2"))
        #expect(NameOrder.lowest(["Pool 10", "Pool 2"]) == "Pool 2")
    }

    /// The letters differ, so the host language cannot decide the order: Danish and Maltese sort
    /// "Aave" before "aave", English after it.
    @Test func `letters order without regard to case`() {
        #expect(NameOrder.isOrderedBefore("balancer", "Curve"))
        #expect(NameOrder.lowest(["Curve", "balancer"]) == "balancer")
    }

    @Test func `a name is not ordered before itself`() {
        #expect(!NameOrder.isOrderedBefore("Aave", "Aave"))
        #expect(NameOrder.lowest(["Aave", "Aave"]) == "Aave")
    }

    @Test func `no names give no lowest name`() {
        #expect(NameOrder.lowest([String]()) == nil)
    }
}
