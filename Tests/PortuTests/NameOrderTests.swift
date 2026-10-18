@testable import Portu
import Testing

/// The name order Platforms and the All Positions protocol filter share (AGENT-DECIDED 8). Each
/// case orders differently under plain `<`, so a comparator that dropped the localized order fails.
struct NameOrderTests {
    @Test func `numbers order by value`() {
        #expect(NameOrder.isOrderedBefore("Pool 2", "Pool 10"))
        #expect(!NameOrder.isOrderedBefore("Pool 10", "Pool 2"))
        #expect(NameOrder.lowest(["Pool 10", "Pool 2"]) == "Pool 2")
    }

    @Test func `lowercase orders before uppercase`() {
        #expect(NameOrder.isOrderedBefore("aave", "Aave"))
        #expect(NameOrder.lowest(["Aave", "aave v3", "aave"]) == "aave")
    }

    @Test func `a name is not ordered before itself`() {
        #expect(!NameOrder.isOrderedBefore("Aave", "Aave"))
        #expect(NameOrder.lowest(["Aave", "Aave"]) == "Aave")
    }

    @Test func `no names give no lowest name`() {
        #expect(NameOrder.lowest([String]()) == nil)
    }
}
