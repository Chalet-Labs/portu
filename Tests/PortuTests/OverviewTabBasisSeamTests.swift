import Foundation
@testable import Portu
import PortuCore
import Testing

/// The position tabs' basis (A7: every list but the donut and Exposure spot is net, Borrowing shows
/// positive debt) and the Key Changes ranking through the production seam.
struct OverviewTabBasisSeamTests {
    private typealias Fixture = OverviewValuationFixture

    /// These tabs admit positive roles only, so their net is their gross: the numbers the list seam
    /// tests pin do not move.
    @Test(arguments: [OverviewPositionTab.keyChanges, .idleStables, .idleMajors])
    func `holding tabs are on the net basis`(tab: OverviewPositionTab) {
        let data = OverviewPositionProjection.tab(tab, context: Fixture.context(), positions: Fixture.positions)

        #expect(!data.groups.isEmpty)
        #expect(data.basis == .net)
        #expect(data.groups.allSatisfy { $0.basis == .net })
    }

    @Test func `the borrowing tab stays on the debt basis`() {
        let data = OverviewPositionProjection.tab(.borrowing, context: Fixture.context(), positions: Fixture.positions)

        #expect(data.basis == .debt)
        #expect(data.groups.allSatisfy { $0.basis == .debt })
    }

    /// PEPE at −90% moves by 10 × −0.9 / 0.1 = −90, more than LINK's +32, so it ranks ahead of LINK.
    @Test func `key changes rank a large loser ahead of smaller gainers`() {
        let changes = Fixture.liveChanges24h.merging(["pepe": Fixture.decimal("-0.9")]) { $1 }
        let tab = OverviewPositionProjection.tab(.keyChanges, context: Fixture.context(liveChanges24h: changes), positions: Fixture.positions)

        #expect(tab.groups.map { $0.tokens.map(\.symbol) } == [["ETH", "PEPE", "LINK"], ["ETH"]])
        #expect(tab.groups.map { $0.tokens.map(\.change24h) } == [[1200, -90, 32], [600]])
    }
}
