import Testing
@testable import PortuUI

@Suite("PortuUI Tests")
struct PortuUITests {
    @Test func themeColors() {
        #expect(PortuTheme.changeColor(for: 1.0) == PortuTheme.gainColor)
        #expect(PortuTheme.changeColor(for: -1.0) == PortuTheme.lossColor)
        #expect(PortuTheme.changeColor(for: 0) == PortuTheme.neutralColor)
    }
}
